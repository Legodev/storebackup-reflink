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
use warnings;


use Digest::MD5 qw(md5_hex);
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

storeBackupCheckBackup.pl - checks if a file in the backup is missing
or corrupted

=head1 SYNOPSIS

	storeBackupCheckBackup.pl -c backupDir [-p number] [-i]
	      [-w filePrefix] [--lastOfEachSeries] 
	      [--includeRenamedBackups] [-T tmpdir]
	      [--logFile
	       [--plusLogStdout] [--suppressTime] [-m maxFilelen]
	       [[-n noOfOldFiles] | [--saveLogs]]

=head1 DESCRIPTION

The tool is intended to find files in the source that might have changed over
time without the users interaction or knowledge, for example by bit rot.

IT calculates md5 sums from the files in the backup and compares
them with md5 sums stored by storeBackup.pl.
It so will recognize, if a file in the backup is missing or currupted.
It only checks plain files, not special files or symbolic links.

=head1 OPTIONS

=over 8

=item B<--print>

    print configuration parameters and stop

=item B<--checkDir>, B<-c>

    backup or top of backups to check

=item B<--backupRoot>, B<-b>

    root of storeBackup tree, normally not needed

=item B<--verbose>, B<-v>

    generate statistics

=item B<--parJobs>, B<-p>

    number of parallel jobs, default = chosen automatically

=item B<--lastOfEachSeries>

    only check the last backup of each series found

=item B<--includeRenamedBackups>, B<-i>

    include renamed backups into the check renamed backups must
    follow the convention <backupDir>-<something>

=item B<--tmpdir>, B<-T>

    directory for temporary files, default is </tmp>

=item B<--wrongFileTables>, B<-w>

    write filenames with detected faults in regular files for
    later bug fixing (not automated)
    parameter to this option is a file prefix
    eg. if the file prefix is '/tmp/bugsB-', the following files are
    generated:
    /tmp/bugsB-files.missing.txt
    /tmp/bugsB-md5sums.missing.txt
    /tmp/bugsB-md5sums.wrong.txt
    if you change option tmpdir to something else, this value will be
    used here instead of /tmp

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

=back

=head1 COPYRIGHT

Copyright (c) 2008-2014 by Heinz-Josef Claes (see README)
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'no',
		    '-list' => [Option->new('-name' => 'checkBackup',
					    '-cl_option' => '-c',
					    '-cl_alias' => '--checkDir',
					    '-param' => 'yes'),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
				Option->new('-name' => 'parJobs',
					    '-cl_option' => '-p',
					    '-cl_alias' => '--parJobs',
					    '-param' => 'yes',
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'print',
					    '-cl_option' => '--print'),
				Option->new('-name' => 'lastOfEachSeries',
					    '-cl_option' => '--lastOfEachSeries'),
				Option->new('-name' => 'includeRenamedBackups',
					    '-cl_option' => '-i',
					    '-cl_alias' =>
					    '--includeRenamedBackups'),
				Option->new('-name' => 'wrongFileTables',
					    '-cl_option' => '-w',
					    '-cl_alias' => '--wrongFileTables',
					    '-param' => 'yes'),
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
				Option->new('-name' => 'tmpdir',
					    '-cl_option' => '-T',
					    '-cl_alias' => '--tmpdir',
					    '-default' => $tmpdir),

# hidden options
# used by storeBackupMount.pl
				Option->new('-name' => 'writeToNamedPipe',
					    '-cl_option' => '--writeToNamedPipe',
					    '-param' => 'yes',
					    '-hidden' => 'yes')
		    ]
    );


$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

# Auswertung der Parameter
my $print = $CheckPar->getOptWithoutPar('print');
my $backupDir = $CheckPar->getOptWithPar('checkBackup');
my $parJobs = $CheckPar->getOptWithPar('parJobs');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $lastOfEachSeries = $CheckPar->getOptWithoutPar('lastOfEachSeries');
my $includeRenamedBackups =
    $CheckPar->getOptWithoutPar('includeRenamedBackups');
my $wrongFileTables = $CheckPar->getOptWithPar('wrongFileTables');
my $logFile = $CheckPar->getOptWithPar('logFile');
my $plusLogStdout = $CheckPar->getOptWithoutPar('plusLogStdout');
my $withTime = not $CheckPar->getOptWithoutPar('suppressTime');
$withTime = $withTime ? 'yes' : 'no';
my $maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
my $noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
my $saveLogs = $CheckPar->getOptWithPar('saveLogs');
$saveLogs = $saveLogs ? 'yes' : 'no';
my $compressWith = $CheckPar->getOptWithPar('compressWith');
$tmpdir = $CheckPar->getOptWithPar('tmpdir');
# hidden options
my $writeToNamedPipe = $CheckPar->getOptWithPar('writeToNamedPipe');


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
	$parJobs *= 3;
    }
    $parJobs = 3 if $parJobs < 3;
}

if ($print)
{
    $CheckPar->print();
    exit 0;
}


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
		   'S:STATISTIC',
		   'D:DEBUG'];
my $prLog1 = printLog->new('-kind' => $prLogKind,
			   @par,
			   '-withTime' => $withTime,
			   '-maxFilelen' => $maxFilelen,
			   '-noOfOldFiles' => $noOfOldFiles,
			   '-saveLogs' => $saveLogs,
			   '-compressWith' => $compressWith,
			   '-tmpdir' => $tmpdir);

my $prLog = printLogMultiple->new('-prLogs' => [$prLog1]);

if ($plusLogStdout)
{
    my $p = printLog->new('-kind' => $prLogKind,
			  '-filedescriptor', *STDOUT,
			  '-tmpdir' => $tmpdir);
    $prLog->add('-prLogs' => [$p]);
}
if ($writeToNamedPipe)
{
    my $np = printLog->new('-kind' => $prLogKind,
			   '-file' => $writeToNamedPipe,
			   '-maxFilelen' => 0,
			   '-tmpdir' => $tmpdir);
    $prLog->add('-prLogs' => [$np]);
}

$prLog->fork($req);


$prLog->print('-kind' => 'E',
	      '-str' => ["missing parameter backupDir\n$Help"],
	      '-exit' => 1)
    unless defined $backupDir;
$backupDir =~ s/\/+\Z//;      # remove / at the end
$prLog->print('-kind' => 'E',
	      '-str' => ["backupDir directory <$backupDir> does not exist " .
	      "or is not accesible"],
	      '-exit' => 1)
    unless -r $backupDir;

$prLog->print('-kind' => 'A',
	      '-str' => ["checking backups in <" .
			 ::absolutePath($backupDir) . ">"]);
$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupCheckBackup.pl, $main::STOREBACKUPVERSION"]);

my (@dirsToCheck) = &::selectBackupDirs($backupDir, $includeRenamedBackups,
					$checkSumFile, $prLog,
					$lastOfEachSeries);

(@main::cleanup) = ($prLog, undef);
$SIG{INT} = \&cleanup;
$SIG{TERM} = \&cleanup;


my $parFork = parallelFork->new('-maxParallel' => $parJobs,
				'-prLog' => $prLog);
my $tinySched = tinyWaitScheduler->new('-prLog' => $prLog);

my $rcsf = undef;
my ($meta, $postfix, $uncompr, @uncomprPar,
    $specialTypeArchiver, $archiveTypes);
my $dirToCheck = undef;
my $jobToDo = 1;
my $parForkToDo = 0;
# statistical data per backup:
my $checkedFiles = 0;
my $checkedFilesSize = 0; # uses size of data in backup (eg. compressed)
my $linkedFiles = 0;
my $linkedFilesSize = 0;  # uses size of data in backup (eg. compressed)
# sums of statistical data:
my $checkedFilesAll = 0;
my $checkedFilesSizeAll = 0;
my $linkedFilesAll = 0;
my $linkedFilesSizeAll = 0;


$main::wft =
    writeBugsToFiles->new('-filePrefix' => $wrongFileTables,
			  '-backupDir' => &::absolutePath($backupDir),
			  '-prLog' => $prLog);

# %usedInodes
## if inode was checked, the inode is used as key, value set to md5sum
## if md5sum check of file has different value that stored in .md5CheckSums,
## inode is marked as 'corrupt' and deleted from that table (so all affected
## files are reported)
# %filesFromMD5CheckSumFile
## key = relative filename
## value pre-set to 1, then changed to 2 if file is not a blocked file
## sub checkAllFiles checks, if all files in the backup are in this hash
# %usedBlockInodes
## stores inodes already used in blocks
my (%usedInodes, %filesFromMD5CheckSumFile, $prevDirToCheck,
    %usedBlockInodes);

while (defined($rcsf) or $jobToDo > 0 or $parForkToDo > 0)
{
#print "--o--0--jobToDo=$jobToDo-parForkToDo=$parForkToDo-\n";
    ############################################################
    my $old = $parFork->checkOne();
    if ($old)
    {
	my ($tmpN, $fn) = @{$old->get('-what' => 'info')};
#print "--o--1-$fn-\n";
	local *IN;
	unless (&::waitForFile($tmpN) or
		open(IN, "< $tmpN"))
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open temporary information file " .
				     "<$tmpN> of <$fn>"]);
	    next;
	}
#print "--o--2-\n";
	my $l;
	while ($l = <IN>)
	{
	    chop $l;
#print "--o--3--$l\n";
	    my ($what, @l) = split(/\s/, $l, 2);
	    if ($what eq 'corrupt')
	    {
		delete $usedInodes{$l[0]};
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["md5 sum mismatch for <$fn>"]);
		$main::wft->print("$fn", 'md5Wrong');
	    }
	    elsif ($what eq 'errors')
	    {
		$prLog->addEncounter('-kind' => 'E',
				     '-add' => $l[0]);
	    }
	    elsif ($what eq 'checkedFiles')
	    {
		$checkedFiles += $l[0];
	    }
	    elsif ($what eq 'checkedFilesSize')
	    {
		$checkedFilesSize += $l[0];
	    }
	    elsif ($what eq 'linkedFiles')
	    {
		$linkedFiles += $l[0];
	    }
	    elsif ($what eq 'linkedFilesSize')
	    {
		$linkedFilesSize += $l[0];
	    }
	    elsif ($what eq 'calcedInodes')
	    {
		while ($l = <IN>)
		{
		    chop $l;
		    my ($inode, $md5) = split(/\s/, $l, 2);
		    $usedBlockInodes{$inode} = $md5;
		}
		last;
	    }
	    else
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["unknown command <$what> in information file " .
			       "<$tmpN> of $fn"]);
	    }
	}

	close(IN);
	unlink $tmpN;
    }
#print "--o--4-\n";

    ############################################################
    $jobToDo = @dirsToCheck;
    if (($rcsf or $jobToDo > 0) and $parFork->getNoFreeEntries() > 0)
    {
#print "----0----open $dirToCheck/$checkSumFile\n";
#print "---jobToDo = $jobToDo, freeEntries=", $parFork->getNoFreeEntries(), ", usedEntries=", $parFork->getNoUsedEntries(), "\n";

	unless ($rcsf)
	{
#print "---0.05---\n";
	    # Wait until all files of the previous actual backup
	    # are calculated. Do this so 
	    if ($parFork->getNoUsedEntries() != 0)
	    {
		$tinySched->wait();
		next;
	    }
	    # ok, all files of old backup are finished,
	    # now begin with the next one
	    if ($verbose)
	    {
		&printStat($prLog, '', $checkedFiles, $checkedFilesSize,
			   $linkedFiles, $linkedFilesSize)
		    if $checkedFilesSize + $linkedFilesSize > 0;
		        # avoid first printout before any checks
	    }
	    $checkedFilesAll += $checkedFiles;
	    $checkedFilesSizeAll += $checkedFilesSize;
	    $linkedFilesAll += $linkedFiles;
	    $linkedFilesSizeAll += $linkedFilesSize;

	    $checkedFiles = 0;
	    $checkedFilesSize = 0;
	    $linkedFiles = 0;
	    $linkedFilesSize = 0;

#print "---0.1---\n";
	    $prevDirToCheck = $dirToCheck;
	    $dirToCheck = shift @dirsToCheck;
	    last unless $dirToCheck;

#print "---0.2---\n";

	    &checkAllFiles($prevDirToCheck, \%filesFromMD5CheckSumFile,
			   $prLog)
		if %filesFromMD5CheckSumFile;
	    %filesFromMD5CheckSumFile = ();

	    $rcsf = readCheckSumFile->new('-checkSumFile' =>
					  "$dirToCheck/$checkSumFile",
					  '-prLog' => $prLog,
					  '-tmpdir' => $tmpdir);
	    $postfix = $rcsf->getInfoWithPar('postfix');
	    my $writeExcludeLog = $rcsf->getInfoWithPar('writeExcludeLog');
	    my $logInBackupDir = $rcsf->getInfoWithPar('logInBackupDir');
	    my $compressLogInBackupDir =
		$rcsf->getInfoWithPar('compressLogInBackupDir');
	    my $logInBackupDirFileName =
		$rcsf->getInfoWithPar('logInBackupDirFileName');
	    $logInBackupDirFileName .= '.bz2'
		if $compressLogInBackupDir eq 'yes';
	     ($uncompr, @uncomprPar) = @{$rcsf->getInfoWithPar('uncompress')};
	    $archiveTypes = $rcsf->getInfoWithPar('archiveTypes');
	    $archiveTypes = '' unless $archiveTypes;
	    $specialTypeArchiver =
		$rcsf->getInfoWithPar('specialTypeArchiver');

	    $filesFromMD5CheckSumFile{'.md5BlockCheckSums.bz2'} = 1;
	    $filesFromMD5CheckSumFile{'.md5CheckSums.bz2'} = 1;
	    $filesFromMD5CheckSumFile{'.md5CheckSums'} = 1;
	    $filesFromMD5CheckSumFile{'.md5CheckSums.Finished'} = 1;
	    $filesFromMD5CheckSumFile{'.md5CheckSums.info'} = 1;
	    $filesFromMD5CheckSumFile{'.storeBackupLinks'} = 1;
	    $filesFromMD5CheckSumFile{'.storeBackup.notSaved.bz2'} = 1
		if $writeExcludeLog eq 'yes';
	    if ($logInBackupDir eq 'yes')
	    {
		if ($logInBackupDirFileName)
		{
		    $filesFromMD5CheckSumFile{$logInBackupDirFileName} = 1;
		}
		else
		{
		    $filesFromMD5CheckSumFile{'.storeBackup.log'} = 1;
		    $filesFromMD5CheckSumFile{'.storeBackup.notSaved.bz2'} = 1;

		    $filesFromMD5CheckSumFile{'.storeBackup.log.bz2'} = 1
			if $compressLogInBackupDir eq 'yes';
		}
	    }

	    $prLog->print('-kind' => 'I',
			  '-str' => ["-- checking <$dirToCheck> ..."]);
#		if $verbose;
	}
	my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	    $size, $uid, $gid, $mode, $f);
	if ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
		 $size, $uid, $gid, $mode, $f) = $rcsf->nextLine()) > 0)
	{
	    $f .= $postfix if $compr eq 'c';
	    $filesFromMD5CheckSumFile{$f} = 1;
	    if ($devInode =~ /\ADEVICE/)   # store path to saved device
	    {
		foreach my $p (&getRelPaths($f))
		{
		    $filesFromMD5CheckSumFile{$p} = 1;
		}
	    }
#print "new file <$f>\n";
#print "    $dirToCheck/$checkSumFile\n";
	    my $filename = "$dirToCheck/$f";
	    if (length($md5sum) == 32)
	    {
#print "-1-$compr-$md5sum-\n";
		if ($compr ne 'b')
		{
		    $filesFromMD5CheckSumFile{$f} = 2; # not a blocked file
		    my ($inode, $sizeBackup) = (stat($filename))[1,7];
#print "-2- inode = $inode, $f\n";
		    if ($inode)
		    {
#print "-2.5- inodes = ", join(' ', keys %usedInodes), "\n";
			if (exists $usedInodes{$inode})
			{
#print "-3-\n";
			    ++$linkedFiles;
			    $linkedFilesSize += $sizeBackup;
#print "-3.1-", ($usedInodes{$inode} ? $usedInodes{$inode} : 'undef') , "\n";
			    if ($usedInodes{$inode} ne $md5sum)
			    {
				$prLog->print('-kind' => 'E',
					      '-str' =>
	              ["calculated md5 sum of <$dirToCheck/$f> is " .
		       "different from the one in " .
		       "<$dirToCheck/.md5BlockCheckSums> (1)"]);
				$main::wft->print("$dirToCheck/$f",
						  'md5Wrong');
			    }
			    else
			    {
				$usedInodes{$inode} = $md5sum;
			    }
#print "-3.2-", $usedInodes{$inode}, "\n";
			    next;
			}
			else
			{
#print "-3.3-", ($usedInodes{$inode} ? $usedInodes{$inode} : 'undef') , "\n";
			    $usedInodes{$inode} = $md5sum;
#print "-3.4-", $usedInodes{$inode}, "\n";
			}		    }
		}
#print "-3.5-filesFromMD5CheckSumFile\{$f\}=", $filesFromMD5CheckSumFile{$f}, "-\n";
#print "\tdevInode=<$devInode>\n";
		unless (-e $filename)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["file <$filename> is missing"]);
		    $main::wft->print($filename, 'fileMissing');
#print "-4-\n";
		    next;
		}
		if (index('ucb', $compr) < 0)
		{
		    $prLog->print('-kind' => 'E',
				  '-print' =>
				  ["unknown value compr =<$compr> at <" .
				   "$dirToCheck/$checkSumFile>, filename = <$f>"]);
#print "-5-\n";
		    next;
		}

#print "-6-\n";
		my $tmpName = &::uniqFileName("$tmpdir/storeBackup-block.");
		$parFork->add_noblock('-function' => \&checkMD5,
				      '-funcPar' =>
				      [$dirToCheck, $filename, $md5sum, $compr,
				       $postfix, $uncompr, \@uncomprPar,
				       \%usedBlockInodes,
				       10*1024**2, $tmpName, $prLog],
				      '-info' => [$tmpName, $filename]);
	    }
	    elsif ($md5sum eq 'dir')
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["directory <$filename> is missing"])
		    unless -e $filename;
		$prLog->print('-kind' => 'E',
			      '-str' => ["<$filename> is not a directory!"])
		    unless -d $filename;
	    }
	    elsif ($md5sum eq 'symlink')
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["<$filename> is missing or not a symlnk!"])
		    unless -l $filename;
	    }
	    elsif ($md5sum eq 'pipe')
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["named pipe <$filename is missing>"])
		    unless -e $filename;
		unless ($specialTypeArchiver and
		    $archiveTypes =~ /p/)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["<$filename> is not a named pipe!"])
			unless -p $filename;
		}
	    }
	    elsif ($md5sum eq 'socket')
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["socket <$filename> is missing"])
		    unless -e $filename;
		unless ($specialTypeArchiver and
		    $archiveTypes =~ /S/)
		{
		    $prLog->print('-kind' => 'E',
			      '-str' => ["<$filename> is not a socket!"])
		    unless -S $filename;
		}
	    }
	    elsif ($md5sum eq 'blockdev')
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["block device <$filename> is missing"])
		    unless -e $filename;
		unless ($specialTypeArchiver and
		    $archiveTypes =~ /p/)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["<$filename> is not a block device!"])
			unless -b $filename;
		}
	    }
	    elsif ($md5sum eq 'chardev')
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["char device <$filename> is missing"])
		    unless -e $filename;
		unless ($specialTypeArchiver and
		    $archiveTypes =~ /p/)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["<$filename> is not a char device!"])
			unless -c $filename;
		}
	    }

#print "-10-$f\n";
	    $tinySched->reset();
	}
	else
	{
#print "-11- rcsf = undef\n";
	    $rcsf = undef;
	}
#print "-10-\n";
    }

    ############################################################
    $tinySched->wait();

    $parForkToDo = $parFork->getNoUsedEntries();
#print "2 parForkToDo = $parForkToDo\n";
}     # end of global while loop over all jobs

&checkAllFiles($dirToCheck, \%filesFromMD5CheckSumFile,
	       $prLog)
    if %filesFromMD5CheckSumFile;


if ($verbose)
{
    &printStat($prLog, '', $checkedFiles, $checkedFilesSize,
	       $linkedFiles, $linkedFilesSize);

    $checkedFilesAll += $checkedFiles;
    $checkedFilesSizeAll += $checkedFilesSize;
    $linkedFilesAll += $linkedFiles;
    $linkedFilesSizeAll += $linkedFilesSize;
    &printStat($prLog, 'overall', $checkedFilesAll, $checkedFilesSizeAll,
	       $linkedFilesAll, $linkedFilesSizeAll);
}

my $enc = $prLog->encountered('-kind' => 'W');
my $S = $enc > 1 ? 'S' : '';
if ($enc)
{
    $prLog->print('-kind' => 'W',
		  '-str' => ["-- $enc WARNING$S OCCURRED DURING THE CHECK! --"])
}
else
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["-- no WARNINGS OCCURRED DURING THE CHECK! --"]);
}

$enc = $prLog->encountered('-kind' => 'E');
$S = $enc > 1 ? 'S' : '';
if ($enc)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["-- $enc ERROR$S OCCURRED DURING THE CHECK! --"]);
}
else
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["-- no ERRORS OCCURRED DURING THE CHECK! --"]);
}



if ($prLog->encountered('-kind' => "E"))
{
    exit 1;
}
else
{
    $prLog->print('-kind' => 'Z',
		  '-str' => ["checking backups in <" .
			     ::absolutePath($backupDir) . ">"]);
    exit 0;
}


############################################################
# checks calculated md5 sum against stored one(s)
# this function is called for all files (blocked and non-blocked
sub checkMD5
{
    my ($dirToCheck, $f, $md5sum, $compr, $postfix, $uncompr, $uncomprPar,
	$usedBlockInodes, $blockSize, $tmpName, $prLog) = @_;

    my (%inode2md5);   # store calculated md5 sum of new inodes

    # statistical data per checkMD5
    my $checkedFiles = 0;
    my $checkedFilesSize = 0;
    my $linkedFiles = 0;
    my $linkedFilesSize = 0;

    local *OUT;
    open(OUT, "> $tmpName") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot open <$tmpName>"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);

#print "checkMD5 -------------$f----------, $md5sum, ", length($md5sum), ", compr=$compr\n";
    my $nrErrors = 0;
    if (length($md5sum) == 32)
    {
	if ($compr eq 'u' or $compr eq 'c')
	{
	    my $md5All = Digest::MD5->new();
	    local *FILE;
	    my $fileIn = undef;
	    unless (-e $f)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["file <$f> is missing"]);
		$main::wft->print($f, 'fileMissing');
		++$nrErrors;
		print OUT "errors $nrErrors\n";
		return 1;
	    }
	    if ($compr eq 'u')
	    {
		unless (sysopen(FILE, $f, O_RDONLY))
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot open <$f>"],
				  '-add' => [__FILE__, __LINE__]);
		    ++$nrErrors;
		    print OUT "errors $nrErrors\n";
		    return 1;
		}
	    }
	    else
	    {
		$fileIn =
		    pipeFromFork->new('-exec' => $uncompr,
				      '-param' => \@uncomprPar,
				      '-stdin' => $f,
				      '-outRandom' => "$tmpdir/stbuPipeFrom10-",
				      '-prLog' => $prLog);
	    }

	    my ($inode, $size) = (stat($f))[1,7];
	    ++$checkedFiles;
	    $checkedFilesSize += $size;
	    my $buffer;
	    while ($fileIn ? $fileIn->sysread(\$buffer, $blockSize) :
		   sysread(FILE, $buffer, $blockSize))
	    {
		$md5All->add($buffer);
	    }

	    if ($md5sum ne $md5All->hexdigest())
	    {
		print OUT "corrupt $inode $f\n";
	    }
	    else
	    {
		# ready
	    }
	    if ($fileIn)
	    {
		$fileIn->close();
		$fileIn = undef;
	    }
	    else
	    {
		close(FILE);
	    }
	}                       # if ($compr eq 'u' or $compr eq 'c')
	elsif ($compr eq 'b')
	{
#print "start checking blocked file $f\n";
	    # read all files in directory
	    local *DIR;
	    unless (opendir(DIR, $f))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot open <$f>"],
			      '-add' => [__FILE__, __LINE__]);
		++$nrErrors;
		print OUT "errors $nrErrors\n";
		return 1;
	    }
	    my ($entry, @entries);
	    while ($entry = readdir DIR)  # one entry per inode
	    {
		next unless $entry =~ /\A\d/;
		
		push @entries, $entry;
	    }
	    close(DIR);
	    my $fileIn =
		pipeFromFork->new('-exec' => 'bzip2',
				  '-param' => ['-d'],
				  '-stdin' => "$f/.md5BlockCheckSums.bz2",
				  '-outRandom' => "$tmpdir/stbuPipeFrom11-",
				  '-prLog' => $prLog);

	    my $l;
	    while ($l = $fileIn->read())
	    {
		chomp $l;
		my ($l_md5, $l_compr, $l_f, $n);
		$n = ($l_md5, $l_compr, $l_f) = split(/\s/, $l, 3);
		if ($n != 3)
		{
		    ++$nrErrors;
		    print OUT "errors $nrErrors\n";
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["strange line in <$f/.md5BlockCheckSums.bz2> " .
				   "in line " . $fileIn->get('-what' => 'lineNr') .
				   ":", "\t<$l>"]);
		}

		if (-e "$dirToCheck/$l_f")
		{
		    my $inode = (stat("$dirToCheck/$l_f"))[1];
		    if (exists $usedBlockInodes{$inode} and
			$usedBlockInodes{$inode} ne $l_md5)
		    {
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["calculated md5 sum of <$dirToCheck/$l_f> " .
				      "is different from the one in the checksum " .
				       "file <$f/.md5BlockCheckSums.bz2> (3)"]);
			$inode2md5{$inode} = $$usedBlockInodes{$inode};
			++$nrErrors;
		    }
		    else
		    {
			$inode2md5{$inode} = $l_md5;
		    }
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["file <$dirToCheck/$l_f> is missing"]);
		    $main::wft->print("$dirToCheck/$l_f", 'fileMissing');
		    ++$nrErrors;
		}
	    }
	    $fileIn->close();
	    $fileIn = undef;

	    my $md5All = Digest::MD5->new();
	    foreach $entry (sort @entries)  # loop over all files in backup
	    {
		my ($inode, $size) = (stat("$f/$entry"))[1,7];

		my $calcMD5 = 0;
		if (exists $$usedBlockInodes{$inode})
		{
#print "+++++++++inode already calculated: $inode = ",
# $usedBlockInodes{$inode}, "\n";
		    ++$linkedFiles;
		    $linkedFilesSize += $size;
		}
		else
		{
		    ++$checkedFiles;
		    $checkedFilesSize += $size;
		    $calcMD5 = 1;
		}

		local *FROM;
		my $fileIn = undef;
		if ($entry =~ /$postfix\Z/)    # compressed block
		{
		    $fileIn =
			pipeFromFork->new('-exec' => $uncompr,
					  '-param' => \@uncomprPar,
					  '-stdin' => "$f/$entry",
					  '-outRandom' => "$tmpdir/stbuPipeFrom12-",
					  '-prLog' => $prLog);
		}
		else           # block not compressed
		{
		    unless (sysopen(FROM, "$f/$entry", O_RDONLY))
		    {
			$prLog->print('-kind' => 'E',
				      '-str' => ["cannot read <$f/$entry>"]);
			++$nrErrors;
			print OUT "errors $nrErrors\n";
			return 1;
		    }
		}
		my $buffer;
		my $md5Block = Digest::MD5->new() if $calcMD5;
		while ($fileIn ? $size = $fileIn->sysread(\$buffer, $blockSize) :
		       sysread(FROM, $buffer, $blockSize))
		{
		    $md5All->add($buffer);
		    $md5Block->add($buffer) if $calcMD5;
		}
		if ($fileIn)
		{
		    $fileIn->close();
		    $fileIn = undef;
		}
		else
		{
		    close(FILE);
		}

		my $digest = $md5Block->hexdigest() if $calcMD5;
		if ($calcMD5)
		{
		    $$usedBlockInodes{$inode} = $digest;
		}
#print "$f/$entry:\n";
#print "\t$digest = digest\n";
#print "\t", $inode2md5{$inode}, " = inode ($inode)\ if $calcMD5\n";
		if (not exists $inode2md5{$inode})
		{
		    ++$nrErrors;
#		    print OUT "errors $nrErrors\n";
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["<$f/$entry> is missing in " .
				   "<$f/.md5BlockCheckSums.bz2>"]);
		    $main::wft->print("$f/$entry", 'md5Missing');
		}
		elsif ($calcMD5 and $digest ne $inode2md5{$inode})
		{
		    ++$nrErrors;
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["calculated md5 sum of <$f/$entry> is " .
				   "different from the one in " .
				   "<$f/.md5BlockCheckSums.bz2> (2)"]);
		    $main::wft->print("$f/$entry", 'md5Wrong');

		}
	    }

	    if ($md5sum ne $md5All->hexdigest())
	    {
		my $inode = (stat($f))[1];
		print OUT "corrupt $inode";
	    }
	    else
	    {
#print "end checking blocked file $f\n";
		# ready
	    }
#print "checked <$f>\n";
	}
    }

    print OUT "errors $nrErrors\n";
    print OUT "checkedFiles $checkedFiles\n";
    print OUT "checkedFilesSize $checkedFilesSize\n";
    print OUT "linkedFiles $linkedFiles\n";
    print OUT "linkedFilesSize $linkedFilesSize\n";

    print OUT "calcedInodes\n";
    my $i;
    foreach $i (keys %inode2md5)
    {
	print OUT "$i ", $inode2md5{$i}, "\n";
    }

    close(OUT);
#    system("cat $tmpName");
    return 0;
}


############################################################
# check if all files in $dir are in the hash
# and if files in $dir are missing in the hash
sub checkAllFiles
{
    my ($dir, $relFiles, $prLog) = @_;

#print "-1- keys relFiles=\n\t", join("\n\t", sort keys %$relFiles), "\n";
    &_checkAllFiles(length($dir)+1, $dir, $relFiles, $prLog);
}


############################################################
sub _checkAllFiles
{
    my ($length, $dir, $relFiles, $prLog) = @_;

#print "-2- _checkAllFiles: $length, $dir\n";

    my $rel = undef;
    if (length($dir) > $length)
    {
	$rel = substr($dir, $length);
#print "\t-3- set1 rel <$rel>\n";
    }
    if ($rel)
    {
#print "\t-4- check1-> <$rel>\n";
	unless (exists $$relFiles{$rel})
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["<$dir/$rel> is not listed in .md5CheckSum (1)"]);
	    $main::wft->print("$dir/$rel", 'md5Missing');
	}
    }

    local *DIR;
    unless (opendir(DIR, $dir))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot opendir <$dir>"]);
	return;
    }
    my $e;
    while ($e = readdir DIR)
    {
	next if ($e eq '.' or $e eq '..');
	my $de = "$dir/$e";
#print "\t-5- de <$de>\n";

# don't care about blocked files, they are already check
# in sub checkMD5

	$rel = substr($de, $length);
#print "\t-10- set2 rel <$rel>\n";
	unless (exists $$relFiles{$rel})
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["<$dir/$rel> is not listed in .md5CheckSum (2)"]);
	    $main::wft->print("$dir/$rel", 'md5Missing');
	}
    }
    closedir(DIR) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot closedir <$dir>"]);
}


##################################################
# package printLogMultiple needs this function
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    exit $exit;
}


##################################################
# print statistical data
sub printStat
{
    my ($prLog, $text, $checkedFiles, $checkedFilesSize,
	$linkedFiles, $linkedFilesSize) = (@_);

    my $checkP = 0;

    $checkP = int($checkedFilesSize * 10000 /
		  ($checkedFilesSize + $linkedFilesSize) +.5) / 100
		  if ($checkedFilesSize + $linkedFilesSize) > 0;

    $prLog->print('-kind' => 'S',
		  '-str' => ["$text checked $checkedFiles files (" .
			     (&::humanReadable($checkedFilesSize))[0] .
			     ") (" . $checkP . "%)",
			     "$text linked files were $linkedFiles (" . 
			     (&::humanReadable($linkedFilesSize))[0] . ")"]);
}

##################################################
# get all directories to a given relative path, eg.
# <a/b//c> -> <a> <a/b> <a/b/c>
sub getRelPaths
{
    my $path = shift;

    $path =~ s#//#/#g;
 
    my (@parts) = split('/', $path);
    my (@res);
    for (my $n = 0 ; $n < @parts ; $n++)
    {
	push @res, join('/', @parts[0..$n]);
    }

    return @res;
}
