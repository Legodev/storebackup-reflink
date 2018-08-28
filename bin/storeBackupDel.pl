#! /usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2003-2014)
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


$main::STOREBACKUPVERSION = undef;


use strict;

use Fcntl qw(O_RDWR O_CREAT);
use File::Copy;
use POSIX;

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
my $keepAll = '30d';
my $keepDuplicate = '7d';
my $checkSumFile = '.md5CheckSums';
my $chmodMD5File = '0600';

=head1 NAME

storeBackupDel.pl - this program deletes backups created by storeBackup

=head1 SYNOPSIS

	storeBackupDel.pl [-f configFile] [--print]
	[-b backupDirectory] [-S series] [--doNotDelete]
	[--deleteNotFinishedDirs] [-L lockFile]
	[--keepAll timePeriod] [--keepWeekday entry] [--keepFirstOfYear]
	[--keepLastOfYear] [--keepFirstOfMonth] [--keepLastOfMonth]
	[--keepFirstOfWeek] [--keepLastOfWeek]
	[--keepDuplicate] [--keepMinNumber] [--keepMaxNumber]
	[-l logFile
	 [--plusLogStdout] [--suppressTime] [-m maxFilelen]
	 [[-n noOfOldFiles] | [--saveLogs]
	 [--compressWith compressprog]]

=head1 WARNING

  !!! USAGE IN PARALLEL WITH storeBackup.pl CAN DESTROY YOUR BACKUPS !!!

=head1 OPTIONS

=over 8

=item B<--file>, B<-f>

    configuration file (instead of parameters)

=item B<--print>

    print configuration read from configuration file and stop

=item B<--backupDir>, B<-b>

    top level directory of all backups (must exist)

=item B<--series>, B<-S>

    directory of backup series
    same parameter as in storeBackup / relative path
    from backupDir, default is 'default'

=item B<--lockFile>, B<-L>

    lock file, if exists, new instances will finish if
    an old is already running, default is $lockFile
    this type of lock files does not work across multiple servers
    and is not designed to separate storeBackup.pl and
    storeBackupUpdateBackup.pl or any other storeBackup
    process in a separate PID space

=item B<--doNotDelete>

    test only, do not delete any backup

=item B<--deleteNotFinishedDirs>

    delete old backups which where not finished
    this will not happen if doNotDelete is set

=item B<--keepAll>

    keep backups which are not older than the specified amount
    of time. This is like a default value for all days in
    --keepWeekday. Begins deleting at the end of the script
    the time range has to be specified in format 'dhms', e.g.
    10d4h means 10 days and 4 hours
    default = $keepAll;

=item B<--keepWeekday>

		    keep backups for the specified days for the specified
		    amount of time. Overwrites the default values choosen in
		    --keepAll. 'Mon,Wed:40d Sat:60d10m' means:
			keep backups of Mon and Wed 40days + 5mins
			keep backups of Sat 60days + 10mins
			keep backups of the rest of the days like spcified in
				--keepAll (default $keepAll)
		    if you also use the 'archive flag' it means to not
		    delete the affected directories via --keepMaxNumber:
		       a10d4h means 10 days and 4 hours and 'archive flag'
		    e.g. 'Mon,Wed:a40d Sat:60d10m' means:
			keep backups of Mon and Wed 40days + 5mins + 'archive'
			keep backups of Sat 60days + 10mins
			keep backups of the rest of the days like specified in
				--keepAll (default $keepAll)

=item B<--keepFirstOfYear>

    do not delete the first backup of a year
    format is timePeriod with possible 'archive flag'

=item B<--keepLastOfYear>

    do not delete the last backup of a year
    format is timePeriod with possible 'archive flag'

=item B<--keepFirstOfMonth>

    do not delete the first backup of a month
    format is timePeriod with possible 'archive flag'

=item B<--keepLastOfMonth>

    do not delete the last backup of a month
    format is timePeriod with possible 'archive flag'

=item B<--firstDayOfWeek>

    default: 'Sun'. This value is used for calculating
    --keepFirstOfWeek and --keepLastOfWeek

=item B<--keepFirstOfWeek>

    do not delete the first backup of a week
    format is timePeriod with possible 'archive flag'

=item B<--keepLastOfWeek>

    do not delete the last backup of a week
    format is timePeriod with possible 'archive flag'

=item B<--keepDuplicate>

    keep multiple backups of one day up to timePeriod
    format is timePeriod, 'archive flag' is not possible
    default = $keepDuplicate;

=item B<--keepMinNumber>

    Keep that miminum of backups. Multiple backups of one
    day are counted as one backup. Default is 10.

=item B<--keepMaxNumber>

    Try to keep only that maximum of backups. If you have
    more backups, the following sequence of deleting will
    happen:
	    - delete all duplicates of a day, beginning with the
              old once, except the oldest of every day
	    - if this is not enough, delete the rest of the backups
	      beginning with the oldest, but *never* a backup with
	      the 'archive flag' or the last backup

=item B<--keepRelative>, B<-R>

    Alternative deletion scheme. If you use this option, all other
    keep options are ignored. Preserves backups depending
    on their *relative* age. Example:
    -R '1d 7d 2m 3m'
        will (try to) ensure that there is always
	- One backup between 1 day and 7 days old
	- One backup between 5 days and 2 months old
	- One backup between 2 months and 3 months old
	If there is no backup for a specified timespan
	(e.g. because the last backup was done more than 2 weeks
	ago) the next older backup will be used for this timespan.

=item B<--logFile>, B<-l>

    log file (default is STDOUT)

=item B<--plusLogStdout>

    if you specify a log file with --logFile you can
    additionally print the output to STDOUT with this flag

=item B<--suppressTime>

    suppress output of time in logfile

=item B<--maxFilelen>, B<-m>

    maximal length of file, default = 1e6

=item B<--noOfOldFiles>, B<-n>

    number of old log files, default = 5

=item B<--saveLogs>

    save log files with date and time instead of deleting the
    old (with [-noOfOldFiles])

=item B<--compressWith>

    compress saved log files (e.g. with 'gzip -9')
    default is 'bzip2'

=back

=head1 COPYRIGHT

Copyright (c) 2003-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $startDate = dateTools->new();

my $CheckPar =
    CheckParam->new('-allowLists' => 'no',
		    '-configFile' => '-f',
		    '-list' => [Option->new('-name' => 'configFile',
					    '-cl_option' => '-f',
					    '-cl_alias' => '--file',
					    '-param' => 'yes'),
                                Option->new('-name' => 'print',
					    '-cl_option' => '--print'),
                                Option->new('-name' => 'backupDir',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupDir',
					    '-cf_key' => 'backupDir',
					    '-must_be' => 'yes',
					    '-param' => 'yes'),
				Option->new('-name' => 'series',
					    '-cl_option' => '-S',
					    '-cl_alias' => '--series',
					    '-cf_key' => 'series',
					    '-default' => 'default'),
				Option->new('-name' => 'lockFile',
					    '-cl_option' => '-L',
					    '-cl_alias' => '--lockFile',
					    '-cf_key' => 'lockFile',
					    '-default' => $lockFile),
				Option->new('-name' => 'doNotDelete',
					    '-cl_option' => '--doNotDelete',
					    '-cf_key' => 'doNotDelete',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'deleteNotFinishedDirs',
					    '-cl_option' => '--deleteNotFinishedDirs',
					    '-cf_key' => 'deleteNotFinishedDirs',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'keepAll',
					    '-cl_option' => '--keepAll',
					    '-cf_key' => 'keepAll',
					    '-default' => $keepAll),
				Option->new('-name' => 'keepWeekday',
					    '-cl_option' => '--keepWeekday',
					    '-cf_key' => 'keepWeekday',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'keepFirstOfYear',
					    '-cl_option' => '--keepFirstOfYear',
					    '-cf_key' => 'keepFirstOfYear',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepLastOfYear',
					    '-cl_option' => '--keepLastOfYear',
					    '-cf_key' => 'keepLastOfYear',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepFirstOfMonth',
					    '-cl_option' => '--keepFirstOfMonth',
					    '-cf_key' => 'keepFirstOfMonth',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepLastOfMonth',
					    '-cl_option' => '--keepLastOfMonth',
					    '-cf_key' => 'keepLastOfMonth',
					    '-param' => 'yes'),
                                Option->new('-name' => 'firstDayOfWeek',
					    '-cl_option' => '--firstDayOfWeek',
					    '-cf_key' => 'firstDayOfWeek',
					    '-default' => 'Sun'),
				Option->new('-name' => 'keepFirstOfWeek',
					    '-cl_option' => '--keepFirstOfWeek',
					    '-cf_key' => 'keepFirstOfWeek',
					    '-param' => 'yes'),
				Option->new('-name' => 'keepLastOfWeek',
					    '-cl_option' => '--keepLastOfWeek',
					    '-cf_key' => 'keepLastOfWeek',
					    '-param' => 'yes'),
                                Option->new('-name' => 'keepDuplicate',
					    '-cl_option' => '--keepDuplicate',
					    '-cf_key' => 'keepDuplicate',
					    '-default' => $keepDuplicate),
                                Option->new('-name' => 'keepMinNumber',
					    '-cl_option' => '--keepMinNumber',
					    '-cf_key' => 'keepMinNumber',
					    '-default' => 10,
					    '-pattern' => '\A\d+\Z'),
                                Option->new('-name' => 'keepMaxNumber',
					    '-cl_option' => '--keepMaxNumber',
					    '-cf_key' => 'keepMaxNumber',
					    '-default' => 0,
					    '-pattern' => '\A\d+\Z'),
                                Option->new('-name' => 'keepRelative',
					    '-cl_option' => '--keepRelative',
					    '-cf_key' => 'keepRelative',
					    '-quoteEval' => 'yes',
					    '-param' => 'yes'),
				Option->new('-name' => 'logFile',
					    '-cl_option' => '-l',
					    '-cl_alias' => '--logFile',
					    '-cf_key' => 'logFile',
					    '-param' => 'yes'),
				Option->new('-name' => 'plusLogStdout',
					    '-cl_option' => '--plusLogStdout',
					    '-cf_key' => 'plusLogStdout',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'suppressTime',
					    '-cl_option' => '--suppressTime',
					    '-cf_key' => 'suppressTime',
					    '-only_if' => "[logFile]",
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'maxFilelen',
					    '-cl_option' => '-m',
					    '-cl_alias' => '--maxFilelen',
					    '-cf_key' => 'maxFilelen',
					    '-default' => 1e6,
					    '-pattern' => '\A[e\d]+\Z',
					    '-only_if' => "[logFile]"),
				Option->new('-name' => 'noOfOldFiles',
					    '-cl_option' => '-n',
					    '-cl_alias' => '--noOfOldFiles',
					    '-cf_key' => 'noOfOldFiles',
					    '-default' => '5',
					    '-pattern' => '\A\d+\Z',
					    '-only_if' =>"[logFile]"),
                                Option->new('-name' => 'saveLogs',
					    '-cl_option' => '--saveLogs',
					    '-cf_key' => 'saveLogs',
					    '-only_if' => "[logFile]",
					    '-cf_noOptSet' => ['yes', 'no']),
                                Option->new('-name' => 'compressWith',
					    '-cl_option' => '--compressWith',
					    '-cf_key' => 'compressWith',
					    '-quoteEval' => 'yes',
					    '-default' => 'bzip2',
					    '-only_if' =>"[logFile]"),
# hidden options
				Option->new('-name' => 'printAll',
					    '-cl_option' => '--printAll',
					    '-hidden' => 'yes'),
				Option->new('-name' => 'todayOpt',
					    '-cl_option' => '--today',
					    '-cf_key' => 'today',
					    '-hidden' => 'yes',
					    '-param' => 'yes'),
# used by storeBackupMount.pl
				Option->new('-name' => 'writeToNamedPipe',
					    '-cl_option' => '--writeToNamedPipe',
					    '-param' => 'yes',
					    '-hidden' => 'yes')
				]
		    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help,
                 '-ignoreAdditionalKeys' => 1
                 );

# Auswertung der Parameter
my $configFile = $CheckPar->getOptWithPar('configFile');
my $print = $CheckPar->getOptWithoutPar('print');

my $backupDir = $CheckPar->getOptWithPar('backupDir');
my $series = $CheckPar->getOptWithPar('series');

my $lockFile = $CheckPar->getOptWithPar('lockFile');
my $doNotDelete = $CheckPar->getOptWithoutPar('doNotDelete');
my $deleteNotFinishedDirs = $CheckPar->getOptWithoutPar('deleteNotFinishedDirs');
$keepAll = $CheckPar->getOptWithPar('keepAll');
my $keepWeekday = $CheckPar->getOptWithPar('keepWeekday');
$keepWeekday = "@$keepWeekday" if defined $keepWeekday;
my $keepFirstOfYear = $CheckPar->getOptWithPar('keepFirstOfYear');
my $keepLastOfYear = $CheckPar->getOptWithPar('keepLastOfYear');
my $keepFirstOfMonth = $CheckPar->getOptWithPar('keepFirstOfMonth');
my $keepLastOfMonth = $CheckPar->getOptWithPar('keepLastOfMonth');
my $firstDayOfWeek = $CheckPar->getOptWithPar('firstDayOfWeek');
my $keepFirstOfWeek = $CheckPar->getOptWithPar('keepFirstOfWeek');
my $keepLastOfWeek = $CheckPar->getOptWithPar('keepLastOfWeek');
$keepDuplicate = $CheckPar->getOptWithPar('keepDuplicate');
my $keepMinNumber = $CheckPar->getOptWithPar('keepMinNumber');
my $keepMaxNumber = $CheckPar->getOptWithPar('keepMaxNumber');
my $keepRelative = $CheckPar->getOptWithPar('keepRelative');
my $logFile = $CheckPar->getOptWithPar('logFile');
my $plusLogStdout = $CheckPar->getOptWithoutPar('plusLogStdout');
my $withTime = not $CheckPar->getOptWithoutPar('suppressTime');
$withTime = $withTime ? 'yes' : 'no';
my $maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
my $noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
my $saveLogs = $CheckPar->getOptWithoutPar('saveLogs') ? 'yes' : 'no';
my $compressWith = $CheckPar->getOptWithPar('compressWith');
# hidden options
my $printAll = $CheckPar->getOptWithoutPar('printAll');
$print = 1 if $printAll;
my $todayOpt = $CheckPar->getOptWithPar('todayOpt');  # format like
my $writeToNamedPipe = $CheckPar->getOptWithPar('writeToNamedPipe');
                                                      # backup dir name

if ($print)
{
    $CheckPar->print('-showHidden' => $printAll);
    exit 0;
}

my $prLog1;
my (@kind) = ('A:BEGIN', 'Z:END','I:INFO', 'W:WARNING', 'E:ERROR',
	      'S:STATISTIC', 'D:DEBUG', 'V:VERSION');

if ($logFile)
{
    $prLog1 = printLog->new('-kind' => \@kind,
			    '-file' => $logFile,
			    '-withTime' => $withTime,
			    '-maxFilelen' => $maxFilelen,
			    '-noOfOldFiles' => $noOfOldFiles);
}
else
{
    $prLog1 = printLog->new('-kind' => \@kind);
}

my $prLog = printLogMultiple->new('-prLogs' => [$prLog1]);

if ($plusLogStdout)
{
    my $p = printLog->new('-kind' => \@kind,,
			  '-filedescriptor', *STDOUT);
    $prLog->add('-prLogs' => [$p]);
}
if ($writeToNamedPipe)
{
    my $np = printLog->new('-kind' => \@kind,
			   '-file' => $writeToNamedPipe,
			   '-maxFilelen' => 0);
    $prLog->add('-prLogs' => [$np]);
}

(@main::cleanup) = ($prLog, undef);
$SIG{INT} = \&cleanup;
$SIG{TERM} = \&cleanup;

$prLog->print('-kind' => 'A',
	      '-str' =>
	      ["starting deletion in <$backupDir>, series <$series>"]);
$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupDel.pl, $main::STOREBACKUPVERSION"]);

$prLog->print('-kind' => 'E',
	      '-str' => ["backupDir directory <$backupDir> does not exist\n$Help"],
	      '-exit' => 1)
    unless -e $backupDir;

my $targetDir = "$backupDir/$series";
$prLog->print('-kind' => 'E',
	      '-str' => ["cannot write to target directory <$targetDir>"],
	      '-exit' => 1)
    unless (-w $targetDir);
$targetDir = ::absolutePath($targetDir);


my $allLinks = lateLinks->new('-dirs' => [$targetDir],
			      '-kind' => 'recursiveSearch',
			      '-verbose' => 0,
			      '-prLog' => $prLog);


#
# lock file überprüfen
#
if ($lockFile)
{
    if (-f $lockFile)
    {
	open(FILE, "< $lockFile") or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot read lock file <$lockFile>"],
			  '-exit' => 1);
	my $pid = <FILE>;
	chop $pid;
	close(FILE);
	$prLog->print('-kind' => 'E',
		      '-str' => ["strange format in lock file <$lockFile>, " .
				 "line is <$pid>"],
		      '-exit' => 1)
	    unless ($pid =~ /\A\d+\Z/o);
	if (kill(0, $pid) == 1)   # alte Instanz läuft noch
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot start, old instance with pid " .
				     "<$pid> is already running"],
			  '-exit' => 1);
	}
	else
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["removing old lock file of process <$pid>"]
			  );
	}
    }

    open(FILE, "> $lockFile") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot create lock file <$lockFile>"],
		      '-exit' => 1);
    print FILE "$$\n";
    close(FILE);
}

my $statDelOldBackupDirs =
    statisticDeleteOldBackupDirs->new('-prLog' => $prLog);
my $today = dateTools->new();
if ($todayOpt)
{
    if ($todayOpt =~ /\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2}).(\d{2}).(\d{2})\Z/)
    {
	$today = dateTools->new('-year' => $1,
				'-month' => $2,
				'-day' => $3,
				'-hour' => $4,
				'-min' => $5,
				'-sec' => $6);
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["$todayOpt (option today) is not a valid date"],
		      '-exit' => 1)
	    unless $today->isValid();
	$prLog->print('-kind' => 'W',
		      '-str' => ["setting today to " .
				 $today->getDateTime()]);
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["format error at option today, must be",
				 "  YYYY.MM.DD_HH.MM.SS"],
		      '-exit' => 1);
    }
}

my $delOld =
    deleteOldBackupDirs->new('-targetDir' => $targetDir,
			     '-doNotDelete' => $doNotDelete,
			     '-deleteNotFinishedDirs' => $deleteNotFinishedDirs,
			     '-checkSumFile' => $checkSumFile,
			     '-prLog' => $prLog,
			     '-today' => $today,
			     '-keepFirstOfYear' => $keepFirstOfYear,
			     '-keepLastOfYear' => $keepLastOfYear,
			     '-keepFirstOfMonth' => $keepFirstOfMonth,
			     '-keepLastOfMonth' => $keepLastOfMonth,
			     '-firstDayOfWeek' => $firstDayOfWeek,
			     '-keepFirstOfWeek' => $keepFirstOfWeek,
			     '-keepLastOfWeek' => $keepLastOfWeek,
			     '-keepAll' => $keepAll,
			     '-keepRelative' => $keepRelative,
			     '-keepWeekday' => $keepWeekday,
			     '-keepDuplicate' => $keepDuplicate,
			     '-keepMinNumber' => $keepMinNumber,
			     '-keepMaxNumber' => $keepMaxNumber,
			     '-statDelOldBackupDirs' => $statDelOldBackupDirs,
			     '-lateLinksParam' => undef,
			     '-allLinks' => $allLinks
			     );

$delOld->checkBackups();

$delOld->deleteBackups();
$statDelOldBackupDirs->print();

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

$prLog->print('-kind' => 'I',
	      '-str' => ["removing lock file <$lockFile>"]);
unlink $lockFile;

$prLog->print('-kind' => 'Z',
	      '-str' =>
	      ["finished deletion in <$backupDir>, series <$series>"]);


exit 0;


##################################################
# package printLogMultiple needs this function
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    exit $exit;
}
