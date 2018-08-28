#!/usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2012-2014)
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


use POSIX;
use strict;
use warnings;



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


require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'version.pl';
require 'fileDir.pl';
require 'storeBackupLib.pl';

my $checkSumFile = '.md5CheckSums';


=head1 NAME

storeBackupCheckSource.pl - compares unchaged files in source with their
                            md5 sums in the backup

=head1 DESCRIPTION

The tool is intended to find files in the source that might have changed over 
time without the users interaction or knowledge, for example by bit rot.

If a file is unchanged (same ctime, mtime, size) in the source directory
compared to the backup, it:

- prints an ERROR message if the md5 sum differs

- prints a WARNING if permissions, uid or gid differs

- prints MISSING if file is not in the source directory (option -v)

- prints INFO if file is identical (option -v)

=head1 SYNOPSIS

    storeBackupCheckSource.pl -s sourceDir -b singleBackupDir [-v]
	      [-w filePrefix]
	      [--logFile
	       [--plusLogStdout] [--suppressTime] [-m maxFilelen]
	       [[-n noOfOldFiles] | [--saveLogs]]

=head1 OPTIONS

=over 8

=item B<--sourceDir>, B<-s>

    source directory of backup when running storeBackup.pl

=item B<--singleBackupDir>, B<-b>

    directory of the backup to compaire sourceDir with
    this must be *one* single backup directory
    (eg. 2012.08.08_02.00.11)

=item B<--verbose>, B<-v>

    also print positive messages (file is identical in source and backup)

=item B<--wrongFileTables>, B<-w>

    write filenames with detected faults in regular files for
    later bug fixing (not automated)
    parameter to this option is a file prefix
    eg. if the file prefix is '/tmp/bugsS-', the following files are
    generated:
    /tmp/bugsS-files.missing.txt
    /tmp/bugsS-md5sums.wrong.txt

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

Copyright (c) 2012-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'no',
		    '-list' => [Option->new('-name' => 'singleBackupDir',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--singleBackupDir',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
                                Option->new('-name' => 'sourceDir',
					    '-cl_option' => '-s',
					    '-cl_alias' => '--sourceDir',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
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
# hidden options
# used by storeBackupMount.pl
				Option->new('-name' => 'writeToNamedPipe',
					    '-cl_option' => '--writeToNamedPipe',
					    '-param' => 'yes',
					    '-hidden' => 'yes')
				]);

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );


my $singleBackupDir = $CheckPar->getOptWithPar('singleBackupDir');
my $sourceDir = $CheckPar->getOptWithPar('sourceDir');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
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
# hidden options
my $writeToNamedPipe = $CheckPar->getOptWithPar('writeToNamedPipe');


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
		   'I:INFO',
		   'V:VERSION',
		   'W:WARNING',
		   'E:ERROR'];
my $printLog = printLog->new('-kind' => $prLogKind,
			     @par,
			     '-withTime' => $withTime,
			     '-maxFilelen' => $maxFilelen,
			     '-noOfOldFiles' => $noOfOldFiles,
			     '-saveLogs' => $saveLogs,
			     '-compressWith' => $compressWith);

my $prLog = printLogMultiple->new('-prLogs' => [$printLog]);

if ($plusLogStdout)
{
    my $p = printLog->new('-kind' => $prLogKind,
			  '-filedescriptor', *STDOUT);
    $prLog->add('-prLogs' => [$p]);
}
if ($writeToNamedPipe)
{
    my $np = printLog->new('-kind' => $prLogKind,
			   '-file' => $writeToNamedPipe,
			   '-maxFilelen' => 0);
    $prLog->add('-prLogs' => [$np]);
}


$prLog->print('-kind' => 'E',
	      '-str' => ["cannot access sourceDir <$sourceDir>"],
	      '-exit' => 1)
    unless -d $sourceDir;

$prLog->print('-kind' => 'E',
	      '-str' => ["this is not a full backup",
			 "please run storeBackupUpdateBackup.pl on <$singleBackupDir>"],
	      '-exit' => 1)
    if -e "$singleBackupDir/.storeBackupLinks/linkFile.bz2";


(@main::cleanup) = ($prLog, undef);
$SIG{INT} = \&cleanup;
$SIG{TERM} = \&cleanup;


$prLog->print('-kind' => 'A',
	      '-str' => ["comparing <$singleBackupDir> with <$sourceDir>"]);
$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupCheckSource.pl, $main::STOREBACKUPVERSION"]);


my $rcsf = readCheckSumFile->new('-checkSumFile' =>
				 "$singleBackupDir/$checkSumFile",
				 '-prLog' => $prLog);

$main::wft =
    writeBugsToFiles->new('-filePrefix' => $wrongFileTables,
			  '-backupDir' => &::absolutePath($sourceDir),
			  '-prLog' => $prLog,
			  '-md5Missing' => 0);

my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
    $size, $uid, $gid, $mode, $filename);
while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	 $size, $uid, $gid, $mode, $filename) = $rcsf->nextLine()) > 0)
{
    if ($devInode =~ /\ADEVICE/)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["ignoring stored device <$filename>"])
	    if $verbose;
	next;
    }

    my $f = "$sourceDir/$filename";
    if (length($md5sum) == 32)   # normal file
    {
	# check if it exists with same time stamp in sourceDir
	if (-e $f)
	{
	    unless (-r $f)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["file <$f> exists but is unreadable"]);
		$main::wft->print(&::absolutePath($f), 'fileMissing');

		next;
	    }
	    my ($actMode, $actUid, $actGid, $actCtime, $actMtime,
		$actAtime, $actSize) =
		    (stat($f))[2, 4, 5, 10, 9, 8, 7];
	    $actMode = 0 unless $actMode;
	    $actMode &= 07777;

	    if ($ctime == $actCtime and $mtime == $actMtime and
		$size == $actSize)
	    {
		my $actMd5 = &::calcMD5($f, $prLog);

		unless ($actMd5)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot calculate md5 sum of <$f>"]);
		    next;
		}
		if ($md5sum eq $actMd5)   # looks good
		{
		    $prLog->print('-kind' => 'I',
				  '-str' => ["<$f> identical to backup"])
			if $verbose;

		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["<$f> has same md5 sum but different permissions " .
				   "than in backup"])
			if ($mode ne $actMode);
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["<$f> has same md5 sum but different uid " .
				   "than in backup"])
			if ($uid ne $actUid);
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["<$f> has same md5 sum but different gid " .
				   "than in backup"])
			if ($gid ne $actGid);
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["<$f> has same ctime / mtime / size " .
				   "as in backup but different md5 sums: $actMd5 in " .
				   "sourceDir ; $md5sum in backup"]);
		    $main::wft->print(&::absolutePath($f), 'md5Wrong');
		}
	    }
	    else
	    {
		my $actMd5 = ($size == $actSize) ? &::calcMD5($f, $prLog) : 0;
		if ($md5sum eq $actMd5)
		{
		    $prLog->print('-kind' => 'I',
				  '-str' =>
				  ["<$f> has different ctime / mtime size " .
				   "but same md5 sum"])
			if $verbose;
		}
		else
		{
		    $prLog->print('-kind' => 'I',
				  '-str' => ["<$f> differs from backup"])
			if $verbose
		}
	    }
	}
	else
	{
	    $prLog->print('-kind' => 'M',
			  '-str' =>
			  ["<$filename> is missing in the source directory"])
		if $verbose;
	}
    }
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

$prLog->print('-kind' => 'Z',
	      '-str' => ["comparing <$singleBackupDir> to <$sourceDir>"]);


if ($prLog->encountered('-kind' => "E"))
{
    exit 1;
}
else
{
    exit 0;
}

exit 0;


##################################################
# package printLogMultiple needs this function
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    exit $exit;
}
