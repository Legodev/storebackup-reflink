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


$main::STOREBACKUPVERSION = undef;


use strict;


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
push @INC, "$req";

require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'version.pl';
require 'fileDir.pl';
require 'forkProc.pl';
require 'humanRead.pl';
require 'dateTools.pl';
require 'evalTools.pl';
require 'storeBackupLib.pl';

my $checkSumFile = '.md5CheckSums';

my $tmpdir = '/tmp';              # default value
$tmpdir = $ENV{'TMPDIR'} if defined $ENV{'TMPDIR'};

=head1 NAME

storeBackupSearch.pl - locates different versions of a file saved with storeBackup.pl.

=head1 SYNOPSIS

	storeBackupSearch.pl -g configFile

	storeBackupSearch.pl -b backupDirDir [-f configFile]
	      [-s rule]  [--absPath] [-w file] [--parJobs number]
	      [-d level] [--once] [--print] [-T tmpdir] [backupRoot . . .]

=head1 DESCRIPTION

You need some basic understanding of linux and perl to use it.

=head1 OPTIONS

=over 8

=item B<--generate>, B<-g>

    generate a config file

=item B<--print>

    print configuration read from configuration file and stop

=item B<--configFile>, B<-f>

    configuration file (instead of or
    additionally to parameters)

=item B<--backupDir> B<-b>

		    top level directory of all backups

=item B<--searchRule>, B<-s>

		    rule for searching
		    see README: 'including / excluding files and directories'

=item B<--absPath>, B<-a>

    write result with absolute path names

=item B<--writeToFile>, B<-w>

    write search result also to file

=item B<--parJobs>, B<-p>

    number of parallel jobs, default = choosen automaticly

=item B<--debug>, B<-d>

    debug level, possible values are 0, 1, 2, default = 0

=item B<--once>, B<-o>

    show every file found only once (depending on md5 sum)

=item B<--tmpdir>, B<-T>

    directory for temporary files, default is </tmp>

=item backupRoot

    Root directories of backups where to search relative
    to backupDir. If no directories are specified, all
    backups below backupDir are choosen.

=back

=head1 COPYRIGHT

Copyright (c) 2008-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

my $templateConfigFile = <<EOC;
# configuration file for storeBackupSearch.pl, version $main::STOREBACKUPVERSION

# You can set a value specified with '-cf_key' (eg. logFiles) and
# continue at the next lines which have to begin with a white space:
# logFiles = /var/log/messages  /var/log/cups/access_log
#      /var/log/cups/error_log
# One ore more white spaces are interpreted as separators.
# You can use single quotes or double quotes to group strings
# together, eg. if you have a filename with a blank in its name:
# logFiles = '/var/log/my strage log'
# will result in one filename, not in three.
# If an option should have *no value*, write:
# logFiles =
# If you want the default value, uncomment it:
# #logFile =
# You can also use environment variables, like \$XXX or \${XXX} like in
# a shell. Single quotes will mask environment variables, while double
# quotes will not.
# You can mask \$, {, }, ", ' with a backslash (\\), eg. \\\$
# Lines beginning with a '#' or ';' are ignored (use this for comments)
#
# You can overwrite settings in the command line. You can remove
# the setting also in the command by using the --unset feature, eg.:
# '--unset doNotDelete' or '--unset --doNotDelete'


# *** param must exist ***
# top level directory of all linked backups
;backupDir=

# *** param must exist ***
# rule for searching
# !!! see README file 'including / excluding files and directories'
# EXAMPLE: 
# searchRule = ( '\$size > &::SIZE("3M")' and '\$uid eq "hjc"' ) or
#    ( '\$mtime > &::DATE("3d4h")' and not '\$file =~ m#/tmp/#' )'
;searchRule=

# root directory of backup relative to backupDir directory
;backupRoot=

# directory for temporary file, default is /tmp
;tmpDir=

# write result with absolute path names
# default is 'no', possible values are 'yes' and 'no'
;absPath=

# write search result also to file
;writeToFile=

# number of parallel jobs, default = choosen automaticly
;parJobs=

# debug level, possible values are 0, 1, 2, default = 0
;debug=

# show every found file only once (depending on md5 sum)
# default is 'no', possible values are 'yes' and 'no'
;once=
EOC
    ;


&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-configFile' => '-f',
		    '-allowLists' => 'yes',
		    '-listMapping' => 'backupRoot',
		    '-list' => [Option->new('-name' => 'configFile',
					    '-cl_option' => '-f',
					    '-cl_alias' => '--configFile',
					    '-param' => 'yes'),
                                Option->new('-name' => 'generate',
					    '-cl_option' => '-g',
					    '-cl_alias' => '--generate',
					    '-param' => 'yes',
					    '-only_if' =>
'not [configFile] and not [backupDir] and not [backupRoot] and not [searchRule]'),
                                Option->new('-name' => 'backupDir',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupDir',
					    '-cf_key' => 'backupDir',
					    '-param' => 'yes'),
				Option->new('-name' => 'searchRule',
					    '-cl_option' => '-s',
					    '-cl_alias' => '--searchRule',
					    '-cf_key' => 'searchRule',
					    '-param' => 'yes',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'writeAbsPath',
					    '-cl_option' => '-a',
					    '-cl_alias' => '--absPath',
					    '-cf_key' => 'absPath',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'writeToFile',
					    '-cl_option' => '-w',
					    '-cl_alias' => '--writeToFile',
					    '-cf_key' => 'writeToFile',
					    '-param' => 'yes'),
				Option->new('-name' => 'parJobs',
					    '-cl_option' => '-p',
					    '-cl_alias' => '--parJobs',
					    '-cf_key' => 'parJobs',
					    '-param' => 'yes',
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'debug',
					    '-cl_option' => '-d',
					    '-cl_alias' => '--debug',
					    '-cf_key' => 'debug',
					    '-default' => 0,
					    '-pattern' => '\A[012]\Z'),
				Option->new('-name' => 'once',
					    '-cl_option' => '-o',
					    '-cl_alias' => '--once',
					    '-cf_key' => 'once',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'print',
					    '-cl_option' => '--print'),
				Option->new('-name' => 'tmpdir',
					    '-cl_option' => '-T',
					    '-cl_alias' => '--tmpdir',
					    '-cf_key' => 'tmpDir',
					    '-default' => $tmpdir),
				Option->new('-name' => 'backupRoot',
					    '-cf_key' => 'backupRoot',
					    '-param' => 'yes'),
# hidden options
				Option->new('-name' => 'printAll',
					    '-cl_option' => '--printAll',
					    '-hidden' => 'yes'),
				Option->new('-name' => 'readNoLines',
					    '-cl_option' => '--readNoLines',
					    '-cf_key' => 'readNoLines',
					    '-hidden' => 'yes',
					    '-default' => 20000)
		    ]
    );


$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

# Auswertung der Parameter
my $configFile = $CheckPar->getOptWithPar('configFile');
my $generateConfigFile = $CheckPar->getOptWithPar('generate');
my $print = $CheckPar->getOptWithoutPar('print');
my $backupDir = $CheckPar->getOptWithPar('backupDir');
my $writeToFile = $CheckPar->getOptWithPar('writeToFile');
my $searchRule = $CheckPar->getOptWithPar('searchRule');    # vector
my $writeAbsPath = $CheckPar->getOptWithoutPar('writeAbsPath');
my $parJobs = $CheckPar->getOptWithPar('parJobs');
my $debug = $CheckPar->getOptWithPar('debug');
my $once = $CheckPar->getOptWithoutPar('once');
$tmpdir = $CheckPar->getOptWithPar('tmpdir');
my (@backupRoot) = $CheckPar->getListPar();

my $printAll = $CheckPar->getOptWithoutPar('printAll');
$print = 1 if $printAll;
my $readNoLines = $CheckPar->getOptWithPar('readNoLines');

unless ($parJobs)
{
    local *FILE;
    if (open(FILE, "/proc/cpuinfo"))
    {
	my $l;
	$parJobs = 1;
	while ($l = <FILE>)
	{
	    $parJobs++ if $l =~ /processor/;
	}
	close(FILE);
    }
    $parJobs = 2 if $parJobs < 2;
}

if ($generateConfigFile)
{
    my $answer = 'yes';
    if (-e $generateConfigFile)
    {
	do
	{
	    print "<$generateConfigFile> already exists. Overwrite?\n",
	    "yes / no -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'yes' and $answer ne 'no');
    }
    exit 0 if $answer eq 'no';

    local *FILE;
    open(FILE, "> $generateConfigFile") or
	die "could not write to <$generateConfigFile>";
    print FILE $templateConfigFile;
    close(FILE);
    exit 0;
}


if ($print)
{
    $CheckPar->print('-showHidden' => $printAll);
}

my $prLog = printLog->new('-kind' => ['I:INFO', 'W:WARNING', 'E:ERROR',
				      'S:STATISTIC', 'D:DEBUG', 'V:VERSION'],
			  '-tmpdir' => $tmpdir);
$main::__prLog = $prLog;   # used in rules
$prLog->fork($req);

$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupSearch.pl, $main::STOREBACKUPVERSION"]);

$prLog->print('-kind' => 'E',
	      '-str' => ["missing parameters backupDir and searchRule\n$Help"],
	      '-exit' => 1)
    unless defined $backupDir and defined $searchRule;
$prLog->print('-kind' => 'E',
	      '-str' => ["missing parameter backupDir\n$Help"],
	      '-exit' => 1)
    unless defined $backupDir;
$prLog->print('-kind' => 'E',
	      '-str' => ["backupDir directory <$backupDir> does not exist " .
	      "or is not accesible"],
	      '-exit' => 1)
    unless -r $backupDir;
$prLog->print('-kind' => 'E',
	      '-str' => ["missing parameter searchRule\n$Help"],
	      '-exit' => 1)
    unless defined $searchRule;


my $sRule = evalInodeRule->new('-line' => $searchRule,
			       '-keyName' => 'search',
			       '-debug' => $debug,
			       '-prLog' => $prLog);

$prLog->print('-kind' => 'I',
	      '-str' => ["searching with rule", '  ' .
			 join(' ', @{$sRule->getLine()})]);

if ($print)
{
    exit 0;
}


my $allLinks = lateLinks->new('-dirs' => [$backupDir],
			      '-kind' => 'recursiveSearch',
			      '-verbose' => 0,
			      '-prLog' => $prLog);

my $allStbuDirs = $allLinks->getAllStoreBackupDirs();


# filter the relevant backups
my (@dirsToSearch) = ();
if (@backupRoot)
{
    my $d;
    foreach $d (@backupRoot)
    {
	unless ($d =~ m#\A/#)
	{
	    $d = "$backupDir/$d";
	}
	$prLog->print('-kind' => 'E',
		      '-str' => ["directory <$d> does not exist " .
				 "or is not accesible"],
		      '-exit' => 1)
	    unless -r $d;
	$d = &::absolutePath($d);
	$prLog->print('-kind' => 'E',
		      '-str' => ["directory <$d> is not a subdirectory " .
				 "of backupDir <$backupDir>"],
		      '-exit' => 1)
	    unless $d =~ /\A$backupDir/;

	# now get all dirs from @$allStbuDirs below $d
	my $a;
	foreach $a (@$allStbuDirs)
	{
	    push @dirsToSearch, $a
		if $a =~ /\A$d\//s or $a =~ /\A$d\z/s;
	}
    }
    (@dirsToSearch) = sort { $a cmp $b } @dirsToSearch;
}
else
{
    (@dirsToSearch) = sort { $a cmp $b } @$allStbuDirs;
}


$prLog->print('-kind' => 'E',
	      '-str' => ["nothing to search, no backup directories specified"],
	      '-exit' => 1)
    unless @dirsToSearch;

{
    my (@out, $d);
    foreach $d (@dirsToSearch)
    {
	push @out, "  $d";
    }
    $prLog->print('-kind' => 'I',
		  '-str' => ["backup directories to search", @out]);
}


my $parFork = parallelFork->new('-maxParallel' => $parJobs,
				'-prLog' => $prLog);
my $tinySched = tinyWaitScheduler->new('-prLog' => $prLog);

#
# search through all directories in @dirsToSearch
#
local *FILE;
open(FILE, "> $writeToFile") or
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot open <$writeToFile> for writing"],
		  '-exit' => 1)
    if $writeToFile;
my ($dirToSearch, %once, $ne, $nb, $s);
foreach $dirToSearch (@dirsToSearch)
{
    unless (-r "$dirToSearch/$checkSumFile" or
	    -r "$dirToSearch/$checkSumFile.bz2")
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["no readable <$checkSumFile> in " .
				 "<$dirToSearch> ... skipping"]);
	next;
    }
#    if (-f "$dirToSearch/$checkSumFile.notFinished")
    unless (&::checkIfBackupWasFinished('-backupDir' => "$dirToSearch",
					    '-prLog' => $prLog,
					'-count' => 40))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["backup <$dirToSearch> not finished" .
				 " ... skipping"]);
	next;
    }

    $nb++;

    $s = "=== searching in <$dirToSearch>:\n";
    
    print $s;
    print FILE $s if $writeToFile and not $writeAbsPath;

    my $rcsf =
	readCheckSumFile->new('-checkSumFile' => "$dirToSearch/$checkSumFile",
			      '-prLog' => $prLog,
			      '-tmpdir' => $tmpdir);
#    my $meta = $rcsf->getMetaValField();
#    my $postfix = ($$meta{'postfix'})->[0];    # postfix for compression
    my $postfix = $rcsf->getInfoWithPar('postfix');

    my $jobToDo = 1;
    my $parForkToDo = 1;
    while ($jobToDo > 0 or $parForkToDo > 0)
    {
	#
	# check for jobs done
	#
	my $old = $parFork->checkOne();
	if ($old)
	{
	    my $tmpName = $old->get('-what' => 'info');
	    local *IN;
	    open(IN, $tmpName) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot open temporary file <$tmpName>"],
			      '-exit' => 1);
	    my $l;
	    while ($l = <IN>)
	    {
		chop $l;
		my ($md5sum, $size, $mode, $ctime, $mtime, $uid, $gid,
		    $filename) = split(/\s+/, $l, 8);

		if ($once)
		{
		    next if exists $once{$md5sum};
		    $once{$md5sum} = 1;
		}

		$filename =~ s/\\0A/\n/og;    # restore '\n'
		$filename =~ s/\\5C/\\/og;    # restore '\\'

		if ($writeAbsPath)
		{
		    $s = "$dirToSearch/$filename\n";
		}
		else
		{
		    $s = "$filename\n";
		}

		print $s;
		print FILE $s if $writeToFile;
	    }
	    close(IN);
	    unlink $tmpName;
	}

	#
	# start a new job
	#
	if ($jobToDo > 0 and $parFork->getNoFreeEntries() > 0)
	{
	    my (@lineBuffer, $i);
	    my $done = 0;
	    # read $readNoLines lines
	    for ($done = $i = 0 ; $i < $readNoLines ; $i++)
	    {
		my $l = $rcsf->nextBinLine();
		unless ($l)
		{
		    $done = 1;
		    last;
		}
		$ne++;
		push @lineBuffer, $l;
	    }
	    $jobToDo = @lineBuffer;
	    my $tmpName = &::uniqFileName("/$tmpdir/storeBackupSearch-");

	    if ($jobToDo)
	    {
		$parFork->add_noblock('-function' => \&checkRule,
				      '-funcPar' =>
				      [$sRule, \@lineBuffer, $prLog, $checkSumFile,
				       $tmpName],
				      '-info' => $tmpName);
		$tinySched->reset();
	    }
	}

	#
	# wait 
	#
	$tinySched->wait();

	$parForkToDo = $parFork->getNoUsedEntries();
    }
}
close(FILE) or
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot close <$writeToFile>"],
		  '-exit' => 1)
    if $writeToFile;

my $s = '';
$s = ", skipped " . scalar @dirsToSearch - $nb . " backup(s)"
    if @dirsToSearch > $nb;
$prLog->print('-kind' => 'I',
	      '-str' => ["checked $ne entries in $nb backups$s"]);

exit 0;



########################################
sub checkRule
{
    my $sRule = shift;
    my $listOfFiles = shift;
    my $prLog = shift;
    my $checkSumFile = shift;
    my $tmpfile = shift;

    local *OUT;
    unless (open(OUT, "> $tmpfile"))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot open temporary file <$tmpfile>"]);
	return 1;                         # ERROR
    }

    my ($l);
    my (%type) = ('dir' => 'd',
		  'symlink' => 'l',
		  'pipe' => 'p',
		  'socket' => 's',
		  'blockdev' => 'b',
		  'chardev' => 'c');
    my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	$size, $uid, $gid, $mode, $filename);
    foreach $l (@$listOfFiles)
    {
	my (@ret) = readCheckSumFile::evalBinLine($l, $prLog, $checkSumFile);
	next if @ret != 12;
	($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	 $size, $uid, $gid, $mode, $filename) = @ret;

	my $type = 'f';
	$type = $type{$md5sum} 	if exists $type{$md5sum};
	if ($sRule->checkRule($filename, $size, $mode, $ctime, $mtime, $uid,
			      $gid, $type) == 1)
	{
	    $filename =~ s/\\/\\5C/og;    # '\\' stored as \5C
	    $filename =~ s/\n/\\0A/sog;   # '\n' stored as \0A

	    print OUT "$md5sum $size $mode $ctime $mtime $uid $gid $filename\n";
	}
    }

    close(OUT);

    return 0;
}
