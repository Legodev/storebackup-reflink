#! /usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2008-2014)
#                 hjclaes@web.de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


use POSIX;
use strict;
use warnings;

use Fcntl qw(O_RDWR O_CREAT);
use POSIX;

$main::STOREBACKUPVERSION = undef;


sub libPath
{
    my $file = shift;

    my $dir;

    # Falls Datei selbst ein symlink ist, solange folgen, bis aufgelöst
    if (-f $file)
    {
	while (-l $file)
	{
	    my $link = readlink($file);

	    if (substr($link, 0, 1) ne "/")
	    {
		$file =~ s/[^\/]+$/$link/;
	    }
	    else
	    {
		$file = $link;
	    }
	}

	($dir, $file) = &splitFileDir($file);
	$file = "/$file";
    }
    else
    {
	print STDERR "<$file> does not exist!\n";
	exit 1;
    }

    $dir .= "/../lib";           # Pfad zu den Bibliotheken
    my $oldDir = `/bin/pwd`;
    chomp $oldDir;
    if (chdir $dir)
    {
	my $absDir = `/bin/pwd`;
	chop $absDir;
	chdir $oldDir;

	return (&splitFileDir("$absDir$file"));
    }
    else
    {
	print STDERR "<$dir> does not exist, exiting\n";
    }
}
sub splitFileDir
{
    my $name = shift;

    return ('.', $name) unless ($name =~/\//);    # nur einfacher Dateiname

    my ($dir, $file) = $name =~ /^(.*)\/(.*)$/s;
    $dir = '/' if ($dir eq '');                   # gilt, falls z.B. /filename
    return ($dir, $file);
}
my ($req, $prog) = &libPath($0);
(@INC) = ($req, @INC);

require 'storeBackupLib.pl';
require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'version.pl';
require 'dateTools.pl';
require 'fileDir.pl';
require 'humanRead.pl';

my $lockFile = '/tmp/storeBackup.lock';   # default value
my $checkSumFile = '.md5CheckSums';
my $blockCheckSumFile = '.md5BlockCheckSums';
my $baseTreeConf = "storeBackupBaseTree.conf";
my $deltaCacheConf = "deltaCache.conf";
my $pB = 'processedBackups';
my $archiveDurationDeltaCache = '99d';
my $autorepairError = 1;

=head1 NAME

storeBackupUpdateBackup.pl - updates / finalizes backups created by storeBackup.pl with option --lateLink, --lateCompress

=head1 SYNOPSIS

	storeBackupUpdateBackup.pl -b backupDirectory [--autorepair]
	      [--print] [--verbose] [--debug] [--lockFile] [--noCompress]
	      [--progressReport number] [--checkOnly] [--copyBackupOnly]
	      [--dontCopyBackup] [-A archiveDurationDeltaCache]
	      [--dontDelInDeltaCache] [--createNewSeries]
	      [--noWarningDiffSeriesInBackupCopy]
	      [--logFile
	       [--plusLogStdout] [--suppressTime] [-m maxFilelen]
	       [[-n noOfOldFiles] | [--saveLogs]]
	       [--compressWith compressprog]]

	storeBackupUpdateBackup.pl --interactive --backupDir topLevlDir
	      [--autorepair] [--print]

	storeBackupUpdateBackup.pl --genBackupBaseTreeConf directory

	storeBackupUpdateBackup.pl --genDeltaCacheConf directory

=head1 WARNING

  !!! USAGE IN PARALLEL WITH storeBackup.pl CAN DESTROY YOUR BACKUPS !!!

=head1 OPTIONS

=over 8

=item B<--interactive>, B<-i>

    interactive mode for reparing / deleting currupted
    backups created with option '--lateLinks'

=item B<--backupDir>, B<-b>

    top level directory of all backups (must exist)

=item B<--autorepair>, B<-a>

    repair simple inconsistencies automaticly without
    requesting the action

=item B<--print>

    print configuration read from configuration file and stop

=item B<--verbose>, B<-v>

    verbose messages

=item B<--debug>, B<-d>

    generate detailed information about the files
    with the linking information in it

=item B<--lockFile>, B<-L>

    lock file, if exist, new instances will finish if
    an old is already running
    If set to the same file as in storeBackup it will
    prevent $prog from running in parallel
    to storeBackup, default is $lockFile
    this type of lock files does not work across multiple servers
    and is not designed to separate storeBackup.pl and
    storeBackupUpdateBackup.pl or any other storeBackup
    process in a separate PID space

=item B<--noCompress>

    maximal number of parallel compress operations,
    default = choosen automatically

=item B<--checkOnly> B<-c>

    do not perform any action, only check consistency

=item B<--copyBackupOnly>

    only do task to replicate incremental (lateLinks)
    backup; no hard linking, compression, etc.

=item B<--dontCopyBackup>

    do not do any replication task to copy
    incremental (lateLink) backups
    NOTE: if used on the master cache, this option disrupts the data
    flow for replication!

=item B<--archiveDurationDeltaCache> B<-A>

    Duration after which already in backupCopy copied and linked
    backups will be deleted. This affects all series in
    deltacaches processedBackups directory.
    The duration has to be specified in format 'dhms', eg.
    10d4h means 10 days and 4 hours, default is 99d
    (similar to option keepAll in storeBackupDel.pl)

=item B<--dontDelInDeltaCache>
    do not delete any backup in deltaCache

=item B<--createNewSeries> B<-C>

    Automatically create new series in deltaCache and the
    replication directory / directories. This is especially useful
    if you use wildcards to specify series name which should be
    added 'on the fly'

=item B<--progressReport>

    print progress report:

=over 4

=item after each 'number' files when compressing

=item after each 'number * 1000' files when linking

=item after each 'number * 10000' files when performing chmod

=back

=item B<--noWarningDiffSeriesInBackupCopy>, B<-N>

    do not write a warning if there is a different set of series
    inside the backup copy (replication directory) than in the
    actual deltaCache

=item B<--logFile>, B<-l>

    logFile, Default: stdout

=item B<--plusLogStdout>

    if you specify a log file with --logFile you can
    additionally print the output to STDOUT with this flag

=item B<--suppressTime>

    suppress output of time in logfile

=item B<--maxFilelen>, B<-m>

    maximal length of log file, default = 1e6

=item B<--noOfOldFiles>, B<-n>

    number of old log files, default = 5

=item B<--saveLogs>

    save log files with date and time instead of deleting the
    old (with [-noOfOldFiles])

=item B<--compressWith>

    compress saved log files (e.g. with 'gzip -9').
    default is 'bzip2'

=item B<--genBackupBaseTreeConf>

    generate a template of the backup-copy configuration file
    for the backup directories (both source and target)

=item B<--genDeltaCacheConf>

    generate a template of the backup-copy configuration file
    for the deltaCache directory

=back

=head1 COPYRIGHT

Copyright (c) 2008-2014 by Heinz-Josef Claes.
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $startDate = dateTools->new();
my $CheckPar =
    CheckParam->new('-list' => [Option->new('-name' => 'backupDir',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupDir',
					    '-param' => 'yes'),
				Option->new('-name' => 'autorepair',
					    '-cl_option' => '--autorepair',
					    '-cl_alias' => '-a'),
                                Option->new('-name' => 'print',
					    '-cl_option' => '--print'),
				Option->new('-name' => 'interactive',
					    '-cl_option' => '-i',
					    '-cl_alias' => '--interactive'),
				Option->new('-name' => 'lockFile',
					    '-cl_option' => '-L',
                                            '-cl_alias' => '--lockFile',
					    '-only_if' => 'not [interactive]',
                                            '-default' => $lockFile),
				Option->new('-name' => 'noCompress',
					    '-cl_option' => '--noCompress',
					    '-param' => 'yes',
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'checkOnly',
					    '-cl_option' => '-c',
					    '-cl_alias' => '--checkOnly',
					    '-only_if' => 'not [interactive]'),
				Option->new('-name' => 'copyBackupOnly',
					    '-cl_option' => '--copyBackupOnly',
					    '-only_if' => 'not [interactive]'),
				Option->new('-name' => 'dontCopyBackup',
					    '-cl_option' => '--dontCopyBackup',
					    '-only_if' => 'not [interactive]'),
				Option->new('-name' => 'archiveDurationDeltaCache',
					    '-cl_option' => '-A',
					    '-cl_alias' => '--archiveDurationDeltaCache',
					    '-cf_key' => 'archiveDurationDeltaCache',
					    '-default' => $archiveDurationDeltaCache,
					    '-only_if' => 'not [interactive]'),
                                Option->new('-name' => 'dontDelInDeltaCache',
					    '-cl_option' => '--dontDelInDeltaCache',
					    '-only_if' => 'not [interactive]'),
				Option->new('-name' => 'createNewSeries',
					    '-cl_option' => '-C',
					    '-only_if' => 'not [interactive]',
					    '-cl_alias' => '--createNewSeries'),
				Option->new('-name' => 'progressReport',
					    '-cl_option' => '--progressReport',
					    '-default' => 0,
					    '-pattern' => '\A\d+\Z'),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-only_if' => 'not [interactive]',
					    '-cl_alias' => '--verbose'),
				Option->new('-name' => 'debug',
					    '-cl_option' => '--debug',
					    '-cl_alias' => '-d',
					    '-only_if' => 'not [interactive]'),
				Option->new('-name' => 'noWarningDiffSeriesInBackupCopy',
					    '-cl_option' => '-N',
					    '-only_if' => 'not [interactive]',
					    '-cl_alias' => '--noWarningDiffSeriesInBackupCopy'),
				Option->new('-name' => 'logFile',
					    '-cl_option' => '-l',
					    '-cl_alias' => '--logFile',
					    '-param' => 'yes',
					    '-only_if' => 'not [interactive]'),
				Option->new('-name' => 'plusLogStdout',
					    '-cl_option' => '--plusLogStdout',
					    '-only_if' => '[logFile]'),
				Option->new('-name' => 'suppressTime',
					    '-cl_option' => '--suppressTime'),
				Option->new('-name' => 'maxFilelen',
					    '-cl_option' => '-m',
					    '-cl_alias' => '--maxFilelen',
					    '-default' => 1e6,
					    '-pattern' => '\A[e\d]+\Z',
                                            '-only_if' =>'[logFile]'),
				Option->new('-name' => 'noOfOldFiles',
					    '-cl_option' => '-n',
					    '-cl_alias' => '--noOfOldFiles',
					    '-default' => '5',
					    '-pattern' => '\A\d+\Z',
                                            '-only_if' =>"[logFile]"),
                                Option->new('-name' => 'saveLogs',
					    '-cl_option' => '--saveLogs',
                                            '-default' => 'no',
                                            '-only_if' => '[logFile]'),
                                Option->new('-name' => 'compressWith',
					    '-cl_option' => '--compressWith',
					    '-quoteEval' => 'yes',
                                            '-default' => 'bzip2',
                                            '-only_if' =>'[logFile]'),
				Option->new('-name' => 'genBackupBaseTreeConf',
					    '-cl_option' => '--genBackupBaseTreeConf',
		    '-only_if' => 'not [backupDir] and not [genDeltaCacheConf]',
					    '-param' => 'yes'),
				Option->new('-name' => 'genDeltaCacheConf',
					    '-cl_option' => '--genDeltaCacheConf',
		    '-only_if' => 'not [backupDir] and not [genBackupBaseTreeConf]',
					    '-param' => 'yes'),
# hidden options
# used by storeBackupMount.pl
				Option->new('-name' => 'writeToNamedPipe',
					    '-cl_option' => '--writeToNamedPipe',
					    '-param' => 'yes',
					    '-hidden' => 'yes'),
				Option->new('-name' => 'skipSync',
					    '-cl_option' => '--skipSync')
				]
		    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

# Auswertung der Parameter
my $autorepair = $CheckPar->getOptWithoutPar('autorepair');
my $print = $CheckPar->getOptWithoutPar('print');
my $interactive = $CheckPar->getOptWithoutPar('interactive');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $debug = $CheckPar->getOptWithoutPar('debug');
$lockFile = $CheckPar->getOptWithPar('lockFile');
my $noCompress = $CheckPar->getOptWithPar('noCompress');
my $checkOnly = $CheckPar->getOptWithoutPar('checkOnly');
my $copyBackupOnly = $CheckPar->getOptWithoutPar('copyBackupOnly');
my $dontCopyBackup = $CheckPar->getOptWithoutPar('dontCopyBackup');
$archiveDurationDeltaCache = $CheckPar->getOptWithPar('archiveDurationDeltaCache');
my $dontDelInDeltaCache = $CheckPar->getOptWithoutPar('dontDelInDeltaCache');
my $createNewSeries = $CheckPar->getOptWithoutPar('createNewSeries');
my $progressReport = $CheckPar->getOptWithPar('progressReport');
my $noWarningDiffSeriesInBackupCopy =
    $CheckPar->getOptWithoutPar('noWarningDiffSeriesInBackupCopy');
my $logFile = $CheckPar->getOptWithPar('logFile');
my $plusLogStdout = $CheckPar->getOptWithoutPar('plusLogStdout');
my $withTime = not $CheckPar->getOptWithoutPar('suppressTime');
$withTime = $withTime ? 'yes' : 'no';
my $maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
my $noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
my $saveLogs = $CheckPar->getOptWithPar('saveLogs');
my $compressWith = $CheckPar->getOptWithPar('compressWith');
my $backupDir = $CheckPar->getOptWithPar('backupDir');
my $genBackupBaseTreeConf = $CheckPar->getOptWithPar('genBackupBaseTreeConf');
my $genDeltaCacheConf = $CheckPar->getOptWithPar('genDeltaCacheConf');
# hidden options
my $writeToNamedPipe = $CheckPar->getOptWithPar('writeToNamedPipe');
my $skipSync = $CheckPar->getOptWithoutPar('skipSync');


unless ($noCompress)
{
    local *FILE;
    if (open(FILE, "/proc/cpuinfo"))
    {
	my $l;
	$noCompress = 1;
	while ($l = <FILE>)
	{
	    $noCompress++ if $l =~ /processor/;
	}
	close(FILE);
    }
    $noCompress = 2 if $noCompress < 2;
}

my $templateBackupBaseTreeConf = <<EOC;
# configuration file for storeBackup backupDir
#

# One ore more white spaces are interpreted as separators.
# You can use single quotes or double quotes to group strings
# together, eg. if you have a filename with a blank in its name:
# logFiles = '/var/log/my strage log'
# will result in one filename, not in three.
# If an option should have *no value*, write:
# logFiles =
# If you want the default value, comment it:
#backupTreeName =
# You can also use environment variables, like \$XXX or \${XXX} like in
# a shell. Single quotes will mask environment variables, while double
# quotes will not.
# You can mask \$, {, }, ", ' with a backslash (\\), eg. \\\$
# Lines beginning with a '#' or ';' are ignored (use this for comments)
#

# name of the backup tree (*** must be specified ***)
;backupTreeName=

# type of backup, possible values are master, copy, none
# default is none which means there is no special tast for it
# (*** must be specified ***)
;backupType=

# list of the series(es) to distribute (copy from or copy to)
# (*** must be specified ***)
;seriesToDistribute=

# path to central distribution directory
# (*** must be specified ***)
;deltaCache=

EOC
    ;


my $templateDeltaCacheConf = <<EOC;
# configuration file for storeBackup backupDir
#

# One ore more white spaces are interpreted as separators.
# You can use single quotes or double quotes to group strings
# together, eg. if you have a filename with a blank in its name:
# logFiles = '/var/log/my strage log'
# will result in one filename, not in three.
# If an option should have *no value*, write:
# logFiles =
# If you want the default value, comment it:
#backupTreeName =
# You can also use environment variables, like \$XXX or \${XXX} like in
# a shell. Single quotes will mask environment variables, while double
# quotes will not.
# You can mask \$, {, }, ", ' with a backslash (\\), eg. \\\$
# Lines beginning with a '#' or ';' are ignored (use this for comments)
#

# where to copy which series
# syntax:
#   first entry: 'name of backup copy'
#   next entries: 'name of series to copy'
;backupCopy0=

;backupCopy1=
;backupCopy2=
;backupCopy3=
;backupCopy4=
;backupCopy5=
;backupCopy6=
;backupCopy7=
;backupCopy8=
;backupCopy9=

EOC
    ;


my $gen;
foreach $gen ($genBackupBaseTreeConf, $genDeltaCacheConf)
{
    next unless $gen;

    my ($confName, $template);
    if ($genBackupBaseTreeConf)
    {
	$confName = "$gen/storeBackupBaseTree.conf";
	$template = $templateBackupBaseTreeConf;
    }
    else
    {
	$confName = "$gen/deltaCache.conf";
	$template = $templateDeltaCacheConf;
    }

    my $answer = 'yes';
    if (-e $confName)
    {
	do
	{
	    print "<$confName> already exists. Overwrite?\n",
	    "yes / no -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'yes' and $answer ne 'no');
    }
    exit 0 if $answer eq 'no';

    local *FILE;
    open(FILE, '>', $confName) or
	die "could not write to <$confName>";
    print FILE $template;
    close(FILE);
    exit 0;
}

die "please specify option <backupDir>\n$Help"
    unless $backupDir;

$backupDir =~ s/\/+$//;


my (@par) = ();
if (defined $logFile)
{
    push @par, ('-file' => $logFile,
		'-multiprint' => 'yes');
}
else
{
    push @par, ('-filedescriptor', *STDOUT);
}

my ($prLogKind) = ['A:BEGIN',
		   'Z:END',
		   'V:VERSION',
		   'I:INFO',
		   'W:WARNING',
		   'E:ERROR',
		   'P:PROGRESS',
		   'S:STATISTIC',
		   'D:DEBUG'];
my $prLog1 = printLog->new('-kind' => $prLogKind,
			   @par,
			   '-withTime' => $withTime,
			   '-maxFilelen' => $maxFilelen,
			   '-noOfOldFiles' => $noOfOldFiles,
			   '-saveLogs' => $saveLogs,
			   '-compressWith' => $compressWith);

my $prLog = printLogMultiple->new('-prLogs' => [$prLog1]);
$prLog->fork($req);

if ($print)
{
    $CheckPar->print();
    exit 0;
}

if ($plusLogStdout)
{
    my $p = printLog->new('-kind' => $prLogKind,
			  '-filedescriptor', *STDOUT);
    $prLog->add('-prLogs' => [$p]);
}
if ($writeToNamedPipe)
{
    my $pl = $prLog;
    my $np = printLog->new('-kind' => $prLogKind,
			   '-file' => $writeToNamedPipe,
			   '-maxFilelen' => 0);
    $prLog = printLogMultiple->new('-prLogs' => [$pl, $np]);
}

if ($interactive)
{
    $verbose = 1;
    $debug = 1;
}

$main::IOCompressDirect = 0;
eval "use IO::Compress::Bzip2 qw(bzip2)";
if ($@)
{
    $prLog->print('-kind' => 'I',
		  '-str' =>
		  ["please install IO::Compress::Bzip2 from " .
		   "CPAN for better performance"]);
}
else
{
    $main::IOCompressDirect = 1;
}


$prLog->print('-kind' => 'A',
	      '-str' =>
	      ["checking references and backup copying in <$backupDir>"]);
$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupUpdateBackup.pl, $main::STOREBACKUPVERSION"]);

&::checkLockFile($lockFile, $prLog);

exit 1
    unless &deleteOldBackupDirs::checkTimeScaleFormat('archiveDurationDeltaCache',
						      $archiveDurationDeltaCache,
						      $prLog, 0);

my (%seriesToCopy);   # $seriesToCopy{series}{backupCopyName}
my $deltaCache = undef;
if (-e "$backupDir/$baseTreeConf" and not $dontCopyBackup)
{
# read storeBackupBaseTree.conf in $backupDir
    my ($backupTreeName, $backupType, $seriesToDistribute);
    ($backupTreeName, $backupType, $seriesToDistribute, $deltaCache) =
	&::readBackupDirBaseTreeConf("$backupDir/$baseTreeConf",
				     &::absolutePath($backupDir), $prLog);

#print "-1----------------=======------------\n";
    # replace wildcards in replicated backup
    my (@readSeries) = &::evalExceptionList_PlusMinus($seriesToDistribute,
					    &::absolutePath($backupDir),
				      "$backupTreeName series", 'series', 1,
					    undef, 1, $prLog);
#print "-1.1------readSeries=@readSeries\n";

#print "backupTreeName = <$backupTreeName>\n";
#print "backupType = <$backupType>\n";
#print "seriesToDistribute = (@$seriesToDistribute)\n";
#print "deltaCache = <$deltaCache>\n";

    # avoid deltaCache and backupDir to be subdirectories of each other
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["deltaCache <$deltaCache> is a subdirectory of " .
		   "backupDir <$backupDir>, please change"],
		  '-exit' => 1)
	if &::isSubDir($deltaCache, $backupDir);
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["backupDir <$backupDir> is a subdirectory of " .
		   "deltaCache <$deltaCache>, please change"],
		  '-exit' => 1)
	if &::isSubDir($backupDir, $deltaCache);

    if ($backupType eq 'copy')
    {
#print "-2----------------=======------------\n";
	# build hash with list of series in replication directory
	my (%readSeries);
#print "readSeries=<@readSeries>\n";
	foreach my $r (@readSeries)
	{
#print "ßßßßßßßßßß$rßßßßß\n";
	    $readSeries{$r} = 1;
	}

	# read deltaCache.conf in $deltaCache
	my $cscFile = "$deltaCache/$deltaCacheConf";
	my (@bc) = &::readDeltaCacheConf($cscFile, $deltaCache, 1, $prLog);

#print "-2.5----------------=======------------\n";
	# generate list with existing series in Delta Cache
	my (@listSeriesExistInDelta) = ();
	foreach my $bc (@bc)
	{
#print "===> $bc[0][0] --------- $backupTreeName\n";
	    if ($bc[0][0] eq $backupTreeName)
	    {
		(@listSeriesExistInDelta) = (@$bc[1..@$bc-1]);
	    }
#print "-3----------+Delta Cache Series++++++@listSeriesExistInDelta++\n";
	}
	# generate missing series directories in replication directory
	# This has to be done 'on the fly' also when using wildcards in series names
	my $createSeries = 0;
	foreach my $d (@listSeriesExistInDelta)
	{
#print "3.5 -- <$d> -- ", (defined $readSeries{$d}), "\n";
	    if ($createNewSeries and not defined $readSeries{$d})
	    {
#print "3.6-- <$backupDir/$d>\n";
		exit 1
		    unless &::makeDirPath("$backupDir/$d", $prLog);
		$createSeries = 1;
	    }
	}
#print "-4----------------=======------------\n";
#print "-4.1------seriesToDistribute=@$seriesToDistribute\n";
	if ($createSeries)
	{
	    # replace wildcards in replicated backup
	    (@readSeries) = &::evalExceptionList_PlusMinus($seriesToDistribute,
						    &::absolutePath($backupDir),
						    "$backupTreeName series", 'series',
						    1, undef, 1, $prLog);
	}
	$seriesToDistribute =\@readSeries;
#print "-4.2------seriesToDistribute=@$seriesToDistribute\n";

	$autorepairError = 0;
#	# read deltaCache.conf in $deltaCache
#	my $cscFile = "$deltaCache/$deltaCacheConf";
#	my (@bc) = &::readDeltaCacheConf($cscFile, $deltaCache, 1, $prLog);

	# check consistency of backupCopy and deltaCache configuration
	my $foundBackupTreeNameFlag = 0;
	foreach my $bc (@bc)
	{
	    my $s;   # set hash with all series to copy to all backupCopies
	    foreach $s (@$bc[1..@$bc-1])
	    {
		$seriesToCopy{$s}{$$bc[0]} = 1;
	                   # series $s has to be copied to $backupTreeName
#print "####set $s -> ", $$bc[0], " = 1\n";
	    }

	    if ($$bc[0] eq $backupTreeName)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["$cscFile: backupDir name <" .
					 $$bc[0] . "> defined twice"],
			      '-exit' => 1)
		    if $foundBackupTreeNameFlag == 1;

		$foundBackupTreeNameFlag = 1;
#print "--@$bc--\n";
		my (%s);
		foreach $s (@$bc[1..@$bc-1])
		{
		    $s{$s} = 1;
		}
		foreach $s (@$seriesToDistribute)
		{
#print "---removing series <$s>\n";
		    if (exists $s{$s})
		    {
			delete $s{$s};
		    }
		    else
		    {
			$prLog->print('-kind' => 'W',
				      '-str' =>
				      ["$cscFile: series <$s> is missing in <" .
				       $$bc[0] . ">, defined in " .
				       "$backupDir/$baseTreeConf"])
			    unless $noWarningDiffSeriesInBackupCopy;
		    }

		}

		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["$backupDir/$baseTreeConf series <" .
			       join('><', sort keys %s) . "> missing in <" .
			       $$bc[0] . ">, defined in $cscFile",
			       "use option --createNewSeries if you want " .
			       "missing series to be created automatically"],
			      '-exit' => 1)
		    if scalar keys %s;
	    }
	}

	# copy backup directories (still in $backupType eq 'copy')
	my $s;
	foreach $s (@$seriesToDistribute)
	{
	    next unless -d "$deltaCache/$s";

	    mkdir "$backupDir/$s"
		unless -d "$backupDir/$s";

	    my (@dirs) = &::readDirStbu("$deltaCache/$s", __FILE__, __LINE__,
		                '\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}\Z',
					$prLog);
	    my $d;
	    foreach $d (@dirs)
	    {
		# search if flag file is already containing this backupCopyName
		local *FILE;
		if (-d "$deltaCache/$s/$d")
		{
#print "=1=$d\n";
		    if (-e "$deltaCache/$s/$d.notFinished")
		    {
#print "=2=$d\n";
			$prLog->print('-kind' => 'W',
				      '-str' =>
				      ["<$deltaCache/$s/$d> not finished"]);
			last;  # do not copy later backups or
			       # hard linking will run into problems
		    }

		    my $found = 0;
		    if (-e "$deltaCache/$s/$d.copied")
		    {
			open(FILE, '<', "$deltaCache/$s/$d.copied") or
			    $prLog->print('-kind' => 'E',
					  '-str' =>
					  ["cannot open <$deltaCache/$s/$d.copied>"],
					  '-exit' => 1);
			my $l;
			foreach $l (<FILE>)
			{
			    chomp $l;
			    $found = 1
				if $l eq $backupTreeName;
			}
			close(FILE);
		    }

		    if ($found)
		    {
			$prLog->print('-kind' => 'I',
				      '-str' =>
				      ["<$backupDir/$s/$d> already copied"])
			    if $verbose;
			next;
		    }
		}

#print "=3=$d\n";
		$prLog->print('-kind' => 'I',
			      '-str' =>
			      ["copying <$deltaCache/$s/$d> to " .
			       "<$backupDir/$s>"]);
		&::copyDir("$deltaCache/$s/$d" => "$backupDir/$s",
			   "/tmp/stbuUpdateBackup-", $prLog, 0);
		open(FILE, '>>', "$deltaCache/$s/$d.copied") or
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["cannot write <$deltaCache/$s/$d.copied>"],
				  '-exit' => 1);
		print FILE "$backupTreeName\n";
		close(FILE);
	    }
#print "=4=\n";
	}
#print "=5=\n";
    }
    elsif ($backupType eq 'master')
    {
	$seriesToDistribute = \@readSeries;

	my $s;
	foreach $s (@$seriesToDistribute)
	{
	    unless (-e "$backupDir/$s")
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["series <$backupTreeName/$s> does not exist"]);
		next;
	    }

	    $prLog->print('-kind' => 'I',
			  '-str' =>
			  ["master backup: checking <$backupTreeName/$s>"]);

	    my (@dirs) = &::readDirStbu("$backupDir/$s", __FILE__, __LINE__,
			       '\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}\Z',
					$prLog);
	    my $entry;
	    foreach $entry (@dirs)
	    {
		next
		    unless -e "$backupDir/$s/$entry/.storeBackupLinks/linkFile.bz2";

		if ((-e "$deltaCache/$s/$entry" or
		     -e "$deltaCache/$s/$entry.copied") and
		    not -e "$deltaCache/$s/$entry.notFinished")
		{
		    $prLog->print('-kind' => 'I',
				  '-str' =>
				  ["\talready copied <$entry> to <$deltaCache>"]);
		    next;
		}

		$prLog->print('-kind' => 'I',
			      '-str' =>
			      ["\tcopying <$entry> to <$deltaCache/$s>"]);

		mkdir "$deltaCache/$s"
		    unless -e "$deltaCache/$s";

		open(FILE, '>', "$deltaCache/$s/$entry.notFinished") or
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["cannot write <$deltaCache/$s/$entry.notFinished>"],
				  '-exit' => 1);
		close(FILE);
		&::copyDir("$backupDir/$s/$entry" => "$deltaCache/$s",
			   "/tmp/stbuUpdateBackup-", $prLog, 0);
		unlink "$deltaCache/$s/$entry.notFinished";
	    }
	}

    }
    elsif ($backupType eq 'none')
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["$backupDir/$baseTreeConf: nothing to do"]);	
    }
} # end read storeBackupBaseTree.conf in $backupDir


exit 0
    if $copyBackupOnly;


if ($interactive)
{
    my $answer;
    do
    {
	print "\nBefore trying to repair any damages of the backup\n",
	"you should make a backup of the files beeing manipulated by\n",
	"this program. Do this by eg. executing\n",
	"# tar cf /savePlace.tar <backup-dirs>/..storeBackupLinks\n",
	"for all affected backup directories or simply all of your backups.\n",
	"continue?\n",
	"yes / no  -> ";
	$answer = <STDIN>;
	chomp $answer;
    } while ($answer ne 'yes' and $answer ne 'no');

    exit 0
	if $answer eq 'no';
}


my $allLinks = lateLinks->new('-dirs' => [$backupDir],
			      '-kind' => 'recursiveSearch',
			      '-checkLinkFromConsistency' => 1,
			      '-verbose' => $verbose,
			      '-debug' => $debug,
			      '-prLog' => $prLog,
			      '-interactive' => $interactive,
			      '-autorepair' => $autorepair,
			      '-autorepairError' => $autorepairError);


if ($checkOnly)
{
    unlink $lockFile;
    exit 0;
}

if ($interactive)
{
    my $answer;
    do
    {
	print "\ncontinue with updating the backup(s)?\n",
	"(compressing and setting hard links)\n",
	"yes / no  -> ";
	$answer = <STDIN>;
	chomp $answer;
    } while ($answer ne 'yes' and $answer ne 'no');

    exit 0
	if $answer eq 'no';
}

#
# set links and compress files
#
my $updateDirFlag = 0;
my (@lateLinkDirs);
my $numberDirsToLink = -1;
my $numberDirsToLinkCount = 0;
while (((@lateLinkDirs) = $allLinks->getAllDirsWithLateLinks()) > 0)
{
#    $numberDirsToLink = @lateLinkDirs
    $numberDirsToLink = $allLinks->getNumLinkTo()
	if $numberDirsToLink == -1;

    my $d;
    foreach $d (sort @lateLinkDirs)
    {
	my $linkToHash = $allLinks->getLinkToHash();
	my $linkFromHash = $allLinks->getLinkFromHash();

#       print "checking <$d>\n";
       if (-e "$d/.storeBackupLinks/linkFile.bz2")
       {
#	   print "\t$d/.storeBackupLinks/linkFile.bz2 exists\n";
	   my $linkToDir;
	   my $needsUpdate = 0;
	   my $hash = $$linkToHash{$d};
	   foreach $linkToDir (sort keys %$hash)
	   {
#	       print "\t\tchecking $linkToDir for linkFile.bz2: ";
	       if (-e "$linkToDir/.storeBackupLinks/linkFile.bz2")
	       {
		   $needsUpdate = 1;
#		   print "needs Update!\n";
		   last;
	       }
	       else
	       {
#		   print "ok, is updated\n";
	       }
	   }
	   if ($needsUpdate == 0)
	   {
#	       print "update $d\n";
	   }
	   else
	   {
	       next;
	   }
       }
       else
       {
	   next;
       }

	$updateDirFlag = 1;
	++$numberDirsToLinkCount;
	::updateBackupDir($d, $noCompress, $progressReport, $prLog,
			  $interactive, "$numberDirsToLinkCount/$numberDirsToLink");

	if (-e "$backupDir/$baseTreeConf")
	{
	    # write message that this backup is completed to deltaCache
	    # (if necessary)
	    my $absBackupDir = &::absolutePath($backupDir);
	    my $aktDir = &::absolutePath($d);

	    my ($aktBackupDir, $aktSeries, $aktBackup, $n);
	    $n = ($aktBackupDir, $aktSeries, $aktBackup) =
		$aktDir =~
		/\A($absBackupDir)\/(.*?)\/(\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2})\Z/;

#print "<$d> ==> <$aktBackupDir> <$aktSeries> <$aktBackup>\n";

	    my ($backupTreeName, $backupType, $seriesToDistribute, $deltaCache) =
		&::readBackupDirBaseTreeConf("$backupDir/$baseTreeConf",
					     &::absolutePath($backupDir), $prLog);
	    # replace wildcards
	    my (@readSeries) = &::evalExceptionList_PlusMinus($seriesToDistribute,
						    &::absolutePath($backupDir),
					    "$backupTreeName series", 'series', 0,
						    undef, 1, $prLog);
	    $seriesToDistribute =\@readSeries;

	    my $found = 0;
	    foreach my $s (@$seriesToDistribute)
	    {
		if ($s eq $aktSeries)
		{
		    $found = 1;
		    last;
		}
	    }

	    if ($found and $backupType eq 'copy')
	    {
#print "<$backupTreeName> --> <$deltaCache> / <$aktSeries> / <$aktBackup> .linked\n";
		open(FILE, '>>', "$deltaCache/$aktSeries/$aktBackup.linked") or
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["cannot write to <$deltaCache/$aktSeries/$aktBackup.linked>"],
				  '-exit' => 1);
		print FILE "$backupTreeName\n";
		close(FILE);
		$prLog->print('-kind' => 'I',
			      '-str' =>
			      ["marked <$aktSeries/$aktBackup> as linked " .
			       "in <$deltaCache>"]);
	    }


	}


	# delete processed files
	my $f = "$d/.storeBackupLinks/linkFile.bz2";
	if ((unlink $f) != 1)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["1 cannot delete <$f>"]);
	}
	else
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["1 deleted <$f>"])
		if $verbose;
	}

	$f = "$d/.storeBackupLinks/linkTo";
	if (-e $f)
	{
	    if ((unlink $f) != 1)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["2 cannot delete <$f>"]);
	    }
	    else
	    {
		$prLog->print('-kind' => 'I',
			      '-str' => ["2 deleted <$f>"])
		    if $verbose;
	    }
	}

#	print "delete linkTo:\n";
#       print "\t$d:\n";
        my $k;
	my $hash = $$linkToHash{$d};
	foreach $k (sort keys %$hash)
	{
	    $f = $$hash{$k};
#	    print "\t\t$k -> ", $$hash{$k}, "\n";

	    if (-e $f)
	    {
		if ((unlink $f) != 1)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["3 cannot delete <$f>"]);
		}
		else
		{
		    $prLog->print('-kind' => 'I',
				  '-str' => ["3 deleted <$f>"])
			if $verbose;
		}
	    }

	    $f = $$linkFromHash{$k}{$d};
#	    print "delete linkFrom: <$f>\n";
	    if ((unlink $f) != 1)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["3 cannot delete <$f>"]);
	    }
	    else
	    {
		$prLog->print('-kind' => 'I',
			      '-str' => ["3 deleted <$f>"])
		    if $verbose;
	    }
	    
	}

        goto nextLoop;
    }

nextLoop:

    $allLinks = lateLinks->new('-dirs' => [$backupDir],
			       '-kind' => 'recursiveSearch',
			       '-checkLinkFromConsistency' => 1,
			       '-verbose' => $verbose,
			       '-debug' => $debug,
			       '-prLog' => $prLog,
			       '-interactive' => $interactive);

}

$prLog->print('-kind' => 'I',
	      '-str' => ["everything is updated, nothing to do"])
    unless $updateDirFlag;


if (-e "$backupDir/$baseTreeConf" and $deltaCache)
{
    #
    # move backups which are copied (and linked)
    # to all backupCopy locations
    #
#print "keys in seriesToCopy = ", join(" ", keys %seriesToCopy), "\n";
    my $s;
    foreach $s (sort keys %seriesToCopy)
    {
#print "++++++series $s+\n";
	next
	    unless -d "$deltaCache/$s";

	# read copy protocol files in backupCopy target
	my (@copied) =
	    &::readDirStbu("$deltaCache/$s", __FILE__, __LINE__,
			   '\A\d{4}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2}\.linked\Z',
				      $prLog);
#print "-1-\n";
	my (@mustBeCopied) = sort keys %{$seriesToCopy{$s}};

	unless (@copied)
	{
	    $prLog->print('-kind' => 'I',
			  '-str' =>
			  ["\tdeltaCache pool of series <$s> is empty:",
			   "\t\t(must be copied to: <" .
			   join('> <', @mustBeCopied) . '>)'])
		if $verbose;
	    next;
	}

	my $c;
	foreach $c (@copied)   # loop over all .linked files in this series
	{
#print "-2-$c-\n";
	    my ($cDir) = $c =~ /^(.+)\.linked$/;
	    local *FILE;
	    open(FILE, '<', "$deltaCache/$s/$c") or
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot open <$deltaCache/$s/$c>"],
			      '-exit' => 1);
#print "\t<", join("> <", @mustBeCopied), ">\n";
#print "\t$c\n";
	    my ($l, @reallyCopied, %reallyCopied);
	    foreach $l (<FILE>)
	    {
		chomp $l;
		push @reallyCopied, $l;
		$reallyCopied{$l} = 1;
	    }
	    close(FILE);
#print "\t\t@reallyCopied\n";

	    my $mvAway = 1;
	    foreach $l (@mustBeCopied)
	    {
		unless (exists $reallyCopied{$l})
		{
		    $prLog->print('-kind' => 'I',
				  '-str' =>
				  ["copying of series <$s> to <$cDir> not finished:",
				   "\tmust be copied to: <" .
				   join('> <', @mustBeCopied) . '>',
				   "\talready copied: <" .
				   join('> <', @reallyCopied) . '>'])
			if $verbose;
		    $mvAway = 0;
		    last;
		}
	    }
	    if ($mvAway and
		-d "$deltaCache/$s/$cDir")  # mv backup
	    {
		$prLog->print('-kind' => 'I',
			      '-str' =>
			      ["backup <$deltaCache/$s/$cDir> copied to <" .
			       join('> <', @reallyCopied) . '>',
			       "\tmoving backup to <$deltaCache/$pB/$s>"]);
		mkdir "$deltaCache/$pB"
		    unless -d "$deltaCache/$pB";
		mkdir "$deltaCache/$pB/$s"
		    unless -d "$deltaCache/$pB/$s";
		&::mvComm("$deltaCache/$s/$cDir" => "$deltaCache/$pB/$s",
			  '/tmp/mvComm-', $prLog);
	    }
	}
    }

    #
    # check if backups in $deltaCache/processedBackups have to be deleted
    #
    my $delDate = dateTools->new();
    $delDate->sub('-str' => $archiveDurationDeltaCache);
    my $delDateStr = $delDate->getDateTime();

    local *DIR;
    my $cspb = "$deltaCache/$pB";
    mkdir $cspb
	unless -d $cspb;
    opendir(DIR, $cspb) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot opendir <$cspb>, exiting"],
			  '-add' => [__FILE__, __LINE__],
			  '-exit' => 1);
    my (@series);
    while ($s = readdir DIR)
    {
	next if ($s eq '.' or $s eq '..');
	my $e = "$cspb/$s";
	next if (-l $e and not -d $e);   # only directories
	next unless -d $e;
	push @series, $s;
    }
    closedir(DIR);

    my $delString;
    if ($dontDelInDeltaCache)
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["do not delete anything in deltaCache " .
		       "<$deltaCache> processedBackups because " .
		       "--dontDelInDeltaCache is set",
		       "\tage for deletion is > $archiveDurationDeltaCache" .
		       " (delete backups older than $delDateStr)"]);
	$delString = 'would be deleted';
    }
    else
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["deleting in deltaCache " .
		       "<$deltaCache> processedBackups",
		       "\tage for deletion is > $archiveDurationDeltaCache" .
		       " (delete backups older than $delDateStr)"]);
	$delString = 'deleting';
    }

    my (@delDirs) = ();
    foreach $s (@series)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["checking series <$s>"]);

	my $dirs =
	    allStoreBackupSeries->new('-rootDir' => "$cspb/$s",
				      '-checkSumFile' => $checkSumFile,
				      '-prLog' => $prLog);
#				      '-absPath' => 0);
	my (@dirs) = $dirs->getAllFinishedDirs();   # oldest first
	my $d;
	foreach $d (@dirs)
	{
	    my ($year, $month, $day, $hour, $min, $sec) = $d =~
		/\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
	    if ($delDate->compare('-year' => $year,
				  '-month' => $month,
				  '-day' => $day,
				  '-hour' => $hour,
				  '-min' => $min,
				  '-sec' => $sec) < 0)
	    {
		$prLog->print('-kind' => 'I',
			      '-str' => ["\t$s -> $d - $delString"]);
		push @delDirs, "$s/$d";
	    }
	    else
	    {
		$prLog->print('-kind' => 'I',
			      '-str' => ["\t$s -> $d - not old enough to delete"]);
	    }
	}
    }
    unless ($dontDelInDeltaCache)
    {
	my ($sumBytes, $sumFiles) = (0, 0);
	foreach my $d (@delDirs)
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["deleting $d ..."]);
	    unlink "$deltaCache/$d.copied", "$deltaCache/$d.linked";
	    my $rdd = recursiveDelDir->new('-dir' => "$cspb/$d",
					   '-prLog' => $prLog);
	    my ($dirs, $files, $bytes, $links, $stayBytes) =
		$rdd->getStatistics();
	    $sumBytes += $bytes;
	    $sumFiles += $files;
	    my ($b) = &::humanReadable($bytes);
	    my ($sb) = &::humanReadable($stayBytes);
	    $prLog->print('-kind' => 'I',
			      '-str' => ["\tfreed $b ($bytes), $files files"]);
	}
	my ($b) = &::humanReadable($sumBytes);
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["sum: freed $b ($sumBytes), $sumFiles files"])
	    if $sumBytes;

    }
}

# Statistik über Dauer und CPU-Verbrauch

my (@l);
my ($user,$system,$cuser,$csystem) = times;
my ($trenn) = "-------+----------+----------";
push @l, sprintf("%-7s|%10s|%10s", " [sec]", "user", "system");
push @l, "$trenn";
push @l, sprintf("%-7s|%10.2f|%10.2f", "process", $user, $system);
push @l, sprintf("%-7s|%10.2f|%10.2f", "childs", $cuser, $csystem);
push @l, "$trenn";
my ($u, $s) = ($cuser + $user, $csystem + $system);
push @l, sprintf("%-7s|%10.2f|%10.2f => %.2f", "sum", $u, $s, $u + $s);

my (@startDate) = ();
if ($startDate)
{
    push @startDate, '           precommand duration = ' .
	$startDate->deltaInStr('-secondDate' => $startDate);
}

my $dEnd = dateTools->new();
my $duration = $startDate->deltaInSecs('-secondDate' => $dEnd);
$duration = 1 if ($duration == 0);   # Minimaler Wert

$prLog->print('-kind' => 'S',
	      '-str' =>
	      ['                      duration = ' .
	       dateTools::valToStr('-sec' => $duration),
	       @l
	       ]);

unlink $lockFile;

unless ($skipSync)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["syncing ..."]);
    system "/bin/sync";
}

$prLog->print('-kind' => 'Z',
	      '-str' =>
	      ["checking references and copying in <$backupDir>"]);

exit 0;


##################################################
# package printLogMultiple needs this function
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    exit $exit;
}


############################################################
sub updateBackupDir
{
    my $dir = shift;
    my $noCompress = shift;
    my $progressReport = shift;
    my $prLog = shift;
    my $interactive = shift;
    my $count = shift;

    #
    # read compress from .md5CheckSum.info
    #
    $prLog->print('-kind' => 'I',
		  '-str' => ["($count) updating <$dir>"]);

    my $rcsf = readCheckSumFile->new('-checkSumFile' =>
				     "$dir/.md5CheckSums",
				     '-prLog' => $prLog);

#    my $meta = $rcsf->getMetaValField();

#    my ($compr, @comprPar) = @{$$meta{'compress'}};
#    my $comprPostfix = ($$meta{'postfix'})->[0];
    my ($compr, @comprPar) = @{$rcsf->getInfoWithPar('compress')};
    my $comprPostfix = $rcsf->getInfoWithPar('postfix');
#print "compr = <$compr>, comprPar = <@comprPar>\n";

    #
    # set links and compress
    #
    my (%md5ToFile);      # store md5sums of copied files because
                          # number of links is exhausted
    my $f = "$dir/.storeBackupLinks/linkFile.bz2";

    return unless -e $f;

    #
    #
    #
    $prLog->print('-kind' => 'I',
		  '-str' => ["phase 1: mkdir, symlink and compressing files"]);

    my $l;
    my $parForkProc = parallelFork->new('-maxParallel' => $noCompress,
					'-prLog' => $prLog,
					'-firstFast' => 1,
					'-maxWaitTime' => .2,
					'-noOfWaitSteps' => 100);

    my $noCompressedFiles = 0;
    my $noMkdir = 0;
    my $noSymLink = 0;
    my ($oldSize, $newSize) = (0, 0);
    my $linkFile = pipeFromFork->new('-exec' => 'bzip2',
				     '-param' => ['-d'],
				     '-stdin' => $f,
				     '-outRandom' => '/tmp/stbuPipeFrom10-',
				     '-prLog' => $prLog);

    while ($l = $linkFile->read())
    {
	next if $l =~ /^#/;
	chomp $l;
	my ($what, $md5) = split(/\s+/, $l, 2);

	if ($what eq 'dir')
	{
	    $md5 =~ s/\0/\n/og;    # name of directory!
	    unless (-d "$dir/$md5")
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot create directory <$dir/$md5>"],
			      '-exit' => 1)
		    unless mkdir "$dir/$md5", 0700;
	    }
	    $noMkdir++;
	}
	elsif ($what eq 'link' or $what eq 'linkblock' or
	    $what eq 'linkSymlink')
	{
	    my $existingFile = $linkFile->read();
	    $existingFile = "$dir/$existingFile";
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["file <$f> ends unexpected at line $."],
			  '-exit' => 1)
		unless $existingFile;

	    my $newLink = $linkFile->read();
	    $prLog->print('-kind' => 'W',
			  '-str' =>
			  ["file <$f> ends unexpected at line $."],
			  '-exit' => 1)
		unless $newLink;
	} 
	elsif ($what eq 'symlink')
	{
	    $md5 =~ s/\0/\n/og;     # file (not md5sum)
	    $md5 = "$dir/$md5";
	    my $target = $linkFile->read();
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["file <$f> ends unexpected at line $."],
			  '-exit' => 1)
		unless $target;
	    chomp $target;
	    $target =~ s/\0/\n/og;
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["cannot create symlink from <$md5> -> <$target>"])
		unless symlink $target, $md5;
	    $noSymLink++;
	}
	elsif ($what eq 'compress')
	{
	    my $file = $linkFile->read();
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["file <$f> ends unexpected at line $."],
			  '-exit' => 1)
		unless $file;
	    chomp $file;

	    $file =~ s/\0/\n/og;
	    $file = "$dir/$file";        # file to compress
	    my $st = (stat($file))[7];
	    $oldSize += $st if defined $st;
	    $noCompressedFiles++;

	    if ($main::IOCompressDirect and
		$compr eq 'bzip2')
	    {
		local *FILEIN;
		sysopen(FILEIN, $file, O_RDONLY) or
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["cannot open <$file> for compression"]);
		my $bz = new IO::Compress::Bzip2("$file$comprPostfix",
						 BlockSize100K => 9);
		my $buffer;
		while (sysread(FILEIN, $buffer, 1025))
		{
		    unless ($bz->syswrite($buffer))
		    {
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["writing to <$file$comprPostfix> failed"]);
		    }
		}
		$bz->flush();
		$bz->eof();
		close(FILEIN);

		$newSize += (stat("$file$comprPostfix"))[7];
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot delete <$file>"])
		    if (unlink $file) != 1;
	    }
	    else
	    {
		my ($old, $new) =
		    $parForkProc->add_block('-exec' => $compr,
					    '-param' => \@comprPar,
					    '-outRandom' => '/tmp/bzip2-',
					    '-stdin' => $file,
					    '-stdout' => "$file$comprPostfix",
					    '-delStdout' => 'no',
					    '-info' => $file);
		if ($old)
		{
		    my $f = $old->get('-what' => 'info');
		    &::waitForFile("$f$comprPostfix");
		    my $out = $old->getSTDERR();
		    $prLog->print('-kind' => 'E',
				  '-str' => ["STDERR of <$compr @comprPar " .
					     "<$f >$f$comprPostfix>:", @$out])
			if (@$out > 0);
		    $newSize += (stat("$f$comprPostfix"))[7];
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot delete <$f>"])
			if (unlink $f) != 1;
		}
	    }
	    $prLog->print('-kind' => 'S',
			  '-str' =>
			  ["compressed $noCompressedFiles files"])
		if ($progressReport and
		    $noCompressedFiles % $progressReport == 0);
	}
	else
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["illegal keyword <$what> " .
				     "at line $. in file <$f>:",
				     "\t<$l>"],
			  '-exit' => 1);
	}
    }
    $linkFile->wait();
    my $out = $linkFile->getSTDERR();
    if (@$out)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["reading linkFile file reports errors:",
				 @$out]);
	exit 1;
    }
    $linkFile->close();
    my $old;
    while ($old = $parForkProc->waitForAllJobs())
    {
	$noCompressedFiles++;
	&::waitForFile("$f$comprPostfix");
 	my $f = $old->get('-what' => 'info');
	$newSize += (stat("$f$comprPostfix"))[7];
	my $out = $old->getSTDERR();
	$prLog->print('-kind' => 'E',
		      '-str' => ["STDERR of <$compr @comprPar " .
				 "<$f >$f$comprPostfix>:", @$out])
	    if (@$out > 0);
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot delete <$f>"])
	    if (unlink $f) != 1;
    }

    my $percent = $oldSize ? $newSize / $oldSize * 100 : 0;
    $prLog->print('-kind' => 'S',
		  '-str' => ["created $noMkdir directories",
			     "created $noSymLink symbolic links",
			     "compressed $noCompressedFiles files",
			     "used " . (&::humanReadable($newSize))[0] .
			     " instead of " . (&::humanReadable($oldSize))[0] .
			     " ($newSize <- $oldSize ; " .
			     (sprintf "%.1f", $percent) . "%)"]);

    #
    # set hard links
    #
    $prLog->print('-kind' => 'I',
		  '-str' => ["phase 2: setting hard links"]);

    my $withBlockedFiles = 0;
    my $noHardLinks = 0;
    my $noCopiedFiles = 0;
    my $pr = $progressReport * 200;
    $linkFile = pipeFromFork->new('-exec' => 'bzip2',
				  '-param' => ['-d'],
				  '-stdin' => $f,
				  '-outRandom' => '/tmp/stbuPipeFrom11-',
				  '-prLog' => $prLog);

    local *BLOCKMD5;
    if (-e "$dir/.md5BlockCheckSums")  # now (5th april 2012) always writes
    {                                  # complete, compressed file. remains
	$withBlockedFiles = 1;         # for compatibility
	open(BLOCKMD5, ">>", "$dir/.md5BlockCheckSums") or
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["cannot append to <$dir/.md5BlockCheckSums>"],
			  '-exit' => 1);
    }

    while ($l = $linkFile->read())
    {
	next if $l =~ /^#/;
	chomp $l;
	my ($what, $md5) = split(/\s+/, $l, 2);
	my $lineNr = $linkFile->get('-what' => 'lineNr');
	if ($what eq 'link')
	{
	    my $existingFile = $linkFile->read();
	    $existingFile = "$dir/$existingFile";
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $existingFile;
	    chomp $existingFile;
	    $existingFile =~ s/\0/\n/og;

	    my $newLink = $linkFile->read();
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $newLink;
	    chomp $newLink;
	    $newLink =~ s/\0/\n/og;
	    $newLink = "$dir/$newLink";
	    $existingFile = $md5ToFile{$md5} if exists $md5ToFile{$md5};
	    if (link $existingFile, $newLink)
	    {
		$noHardLinks++;
		$prLog->print('-kind' => 'S',
			      '-str' => ["linked $noHardLinks files"])
			if ($pr and $noHardLinks % $pr == 0);
	    }
	    else
	    {
		# copy file
                unless (&::copyFile("$existingFile", "$newLink", $prLog))
                {
                    $prLog->print('-kind' => 'E',
                                  '-str' => ["could not link/copy " .
					     "$existingFile $newLink"]);
                    next;
                }
		$noCopiedFiles++;
		$md5ToFile{$md5} = $newLink;
	    }
	}
	elsif ($what eq 'dir')
	{
	}
	elsif ($what eq 'compress' or $what eq 'symlink')
	{
	    my $file = $linkFile->read();
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $file;
	}
	elsif ($what eq 'linkSymlink')
	{
	    my $existingFile = $linkFile->read();
	    $existingFile = "$dir/$existingFile";
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $existingFile;
	    chomp $existingFile;
	    $existingFile =~ s/\0/\n/og;

	    my $newLink = $linkFile->read();
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $newLink;
	    chomp $newLink;
	    $newLink =~ s/\0/\n/og;
	    $newLink = "$dir/$newLink";
	    if (link $existingFile, $newLink)
	    {
		$noHardLinks++;
		$prLog->print('-kind' => 'S',
			      '-str' => ["linked $noHardLinks files"])
			if ($pr and $noHardLinks % $pr == 0);
	    }
	    else
	    {
		# create symlink
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot create symlink from <$newLink> -> <$md5>"])
		unless symlink $md5, $newLink;
	    $noSymLink++;
	    }
	}
	elsif ($what eq 'linkblock')
	{
	    my $existingFile = $linkFile->read();
	    $existingFile = "$dir/$existingFile";
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $existingFile;
	    chomp $existingFile;
	    $existingFile =~ s/\0/\n/og;

	    my $newLink = $linkFile->read();
	    $newLink = "$dir/$newLink";
	    $prLog->print('-kind' => 'E',
			  '-str' => ["file <$f> ends unexpected at line $lineNr"],
			  '-exit' => 1)
		unless $newLink;
	    chomp $newLink;
	    $newLink =~ s/\0/\n/og;

	    $noHardLinks +=
		&::hardLinkDir($existingFile, $newLink, '\A\d.*',
			       undef, undef, undef, $prLog);

	    if ($withBlockedFiles)
	    {
		my $blockLocal =
		    pipeFromFork->new('-exec' => 'bzip2',
				      '-param' => ['-d'],
				      '-stdin' => "$newLink/.md5BlockCheckSums.bz2",
				      '-outRandom' => '/tmp/stbuPipeFrom12-',
				      '-prLog' => $prLog);

		my $l;
		while ($l = $blockLocal->read())
		{
		    print BLOCKMD5 $l;
		}
		$blockLocal->wait();
		my $out = $blockLocal->getSTDERR();
		if (@$out)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["reading linkFile file reports errors:",
					     @$out]);
		    exit 1;
		}
		$blockLocal->close();
	    }
	}
	else
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["illegal keyword <$what> " .
				     "at line $lineNr in file <$f>:",
			             "\t<$l>"],
			  '-exit' => 1);
	}

    }
    if ($withBlockedFiles)
    {
	close(BLOCKMD5) or
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["cannot close file <$dir/.md5BlockCheckSums>"],
			  '-exit' => 1);
    }
    $linkFile->wait();
    $out = $linkFile->getSTDERR();
    if (@$out)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["reading linkFile file reports errors:",
				 @$out]);
	exit 1;
    }
    $linkFile->close();
    $prLog->print('-kind' => 'S',
		  '-str' => ["linked $noHardLinks files"]);
    $prLog->print('-kind' => 'S',
		  '-str' => ["copied $noCopiedFiles files"])
	if $noCopiedFiles;

    my $comprMd5BlockCheckSums;
    if ($withBlockedFiles and -e "$dir/.md5CheckSums.bz2")
    {
	# compress .md5BlockCheckSums
	$comprMd5BlockCheckSums =
	    forkProc->new('-exec' => 'bzip2',
			  '-param' => ["$dir/.md5BlockCheckSums"],
			  '-outRandom' =>
			  '/tmp/stbu-compr-',
			  '-prLog' => $prLog);
    }

    #
    # set file permissions
    #
    my $preservePerms =
	$rcsf->getInfoWithPar('preservePerms') eq 'no' ? 0 : 1;
    $pr = $progressReport * 2000;
    if ($preservePerms)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["phase 3: setting file permissions"]);
	my $comprPostfix = $rcsf->getInfoWithPar('postfix');

	my $noFiles = 0;
	my $rcsf = readCheckSumFile->new('-checkSumFile' => "$dir/.md5CheckSums",
					 '-prLog' => $prLog);
	my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	    $size, $uid, $gid, $mode, $f);
	while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime,
		 $atime, $size, $uid, $gid, $mode, $f) = $rcsf->nextLine()) > 0)
	{
	    my $file = "$dir/$f";
	    next if ($md5sum eq 'dir');

	    $file .= $comprPostfix if $compr eq 'c';

	    if (not -l $file and not -e $file)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot access <$file>"]);
		next;
	    }
	    $noFiles++;
	    $prLog->print('-kind' => 'S',
			  '-str' => ["set permissions of $noFiles files"])
			if ($pr and $noFiles % $pr == 0);

	    next if $md5sum eq 'symlink';

	    utime $atime, $mtime, $file;
	    chown $uid, $gid, $file;
	    if ($compr eq 'b')         # block file
	    {
		local *BFDIR;
		opendir(BFDIR, $file) or
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["cannot opendir <$file> to set permissions"],
				  '-add' => [__FILE__, __LINE__]);
		my $bfentry;
		while ($bfentry = readdir BFDIR)
		{
		    if ($bfentry =~ /\A\.md5BlockCheckSums/)
		    {
			chmod 0644, "$file/$bfentry";
		    }
		    else
		    {
			utime $atime, $mtime, "$file/$bfentry";
			chown $uid, $gid, "$file/$bfentry";
			chmod $mode, "$file/$bfentry";
		    }
		    $noFiles++;
		}
		closedir(BFDIR);

		$mode &= 0777;    # strip special permissions
		$mode |= 0111;    # add directory permissions
	    }
	    chmod $mode, $file;
	}

	$prLog->print('-kind' => 'S',
		      '-str' => ["set permissions for $noFiles files"]);
    }
    else
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["phase 3: file permissions not set because " .
				 "preservePerms not set in storeBackup.pl"]);
    }

    if ($withBlockedFiles and -e "$dir/.md5CheckSums.bz2")
    {
	# compress .md5BlockCheckSums
	$comprMd5BlockCheckSums->wait();
	my $out = $comprMd5BlockCheckSums->getSTDOUT();
	$prLog->print('-kind' => 'W',
		      '-str' => ["STDERR of <uname>:", @$out])
	    if (@$out > 0);
	$out = $comprMd5BlockCheckSums->getSTDERR();
	$prLog->print('-kind' => 'E',
		      '-str' => ["STDERR of <uname>:", @$out])
	    if (@$out > 0);
    }

    #
    # set directory permissions
    #
    if ($preservePerms)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["phase 4: setting directory permissions"]);
#	my $comprPostfix = ($$meta{'postfix'})->[0];
	my $comprPostfix = $rcsf->getInfoWithPar('postfix');

	my $noDirs = 0;
	my $rcsf = readCheckSumFile->new('-checkSumFile' => "$dir/.md5CheckSums",
					 '-prLog' => $prLog);
	my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	    $size, $uid, $gid, $mode, $f);
	while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime,
		 $atime, $size, $uid, $gid, $mode, $f) = $rcsf->nextLine()) > 0)
	{
	    my $file = "$dir/$f";
	    if ($md5sum eq 'dir')
	    {
		unless (-e $file)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot access <$file>"]);
		    next;
		}
		chown $uid, $gid, $file;
		chmod $mode, $file;
		utime $atime, $mtime, $file;

		$noDirs++;
		$prLog->print('-kind' => 'S',
			  '-str' => ["set permissions of $noDirs directories"])
			if ($pr and $noDirs % $pr == 0);
	    }
	}

	$prLog->print('-kind' => 'S',
		      '-str' => ["set permissions for $noDirs directories"]);
    }
    else
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["phase 4: directory permissions not set because " .
				 "preservePerms not set in storeBackup.pl"]);
    }

}
