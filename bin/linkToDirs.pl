#! /usr/bin/env perl

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


use POSIX;
use strict;
use warnings;

use Fcntl qw(O_RDWR O_CREAT);
use POSIX;

$main::STOREBACKUPVERSION = undef;

use DB_File;           # Berkeley DB


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
require 'fileDir.pl';
require 'dateTools.pl';

my $tmpdir = '/tmp';              # default value
$tmpdir = $ENV{'TMPDIR'} if defined $ENV{'TMPDIR'};



# linkToDirs.pl $main::STOREBACKUPVERSION

=head1 NAME

linkToDirs.pl - hard links files in directories with others

=head1 SYNOPSIS

	linkToDirs.pl [--linkWith copyBackupDir] [--linkWith ...]
		      --targetDir targetForSourceDir
		      [--progressReport number[,timeframe]] 
		       [--printDepth] [--dontLinkSymlinks]
		      [--ignoreErrors] [--saveRAM] [-T tmpdir]
		      [--createSparseFiles [--blockSize]]
		      sourceDir ...

=head1 DESCRIPTION

Make a de-duplicated copy of files in one directory to another location. 
Utilizes hard links to the full extent possible to avoid wasting storage
space.

Usage note: whereas many file copy utilities have just two primary parameters
(the source and destination), linkToDirs.pl allows three primary parameters:
    * source (sourceDir)
    * destination (targetDir)
    * and a reference location (linkWith [optional])
The reference location is the place to look for existing content which
can be hard linked to. Files with the same contents in sourceDir are hard
linked always in targetDir.

=head1 OPTIONS

=over 8

=item B<--linkWith>, B<-w>

    linkWith target; the backups where other backups have to be
    linked to use this parameter multiple times for multiple
    directories
    if you do not use this option, the program will just copy and
    link 'sourceDir'

=item B<--targetDir>, B<-t>

    path(s) to directory where backups specified by
    --sourceDir should be placed

=item B<--progressReport>, B<-P>

    print progress report after each 'number' files
    additional you may add a time frame after which a message is
    printed
    if you want to print a report each 1000 files and after
    one minute and 10 seconds, use: -P 1000,1m10s

=item B<--printDepth>, B<-D>

    print depth of actual read directory during backup

=item B<--dontLinkSymlinks>

    do not hard link identical symbolic links

=item B<--ignoreErrors>, B<-i>

    if set, don't stop in case of errors when copying

=item B<--saveRAM>

    write temporary dbm files in --tmpdir
    use this if you do not have enough RAM

=item B<--tmpdir>, B<-T>

    directory for temporary files, default is </tmp>

=item B<--createSparseFiles>, B<-s>

    if a file is indicated as a sparse file and that file has to be
    copied, then external program 'cp' is called to copy that file
    (gnucp / linux does some inspection about sparse files, if your
    OS related version of cp does not support this functionality,
    then this option will not work for you)

=item B<--blockSize>

    block size used to check if a file is / may be a sparse file
    default is 512 bytes (which should be fine for most file systems)
    
=item B<sourceDir>

    path(s) to directories which have to be linked to other backups
    use this parameter multiple times for multiple directories

=back

=head1 COPYRIGHT

Copyright (c) 2012-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut


my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'yes',
		    '-list' => [Option->new('-name' => 'linkWith',
					    '-cl_option' => '-w',
					    '-cl_alias' => '--linkWith',
					    '-param' => 'yes',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'targetDir',
					    '-cl_option' => '-t',
					    '-cl_alias' => '--targetDir',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'progressReport',
					    '-cl_option' => '--progressReport',
					    '-cl_alias' => '-P',
					    '-cf_key' => 'progressReport',
					    '-default' => 0),
				Option->new('-name' => 'printDepth',
					    '-cl_option' => '--printDepth',
					    '-cl_alias' => '-D',
					    '-cf_key' => 'printDepth',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'dontLinkSymlinks',
					    '-cl_option' => '--dontLinkSymlinks'),
				Option->new('-name' => 'ignoreErrors',
					    '-cl_option' => '-i',
					    '-cl_alias' => '--ignoreErrors'),
				Option->new('-name' => 'saveRAM',
					    '-cl_option' => '--saveRAM'),
				Option->new('-name' => 'createSparseFiles',
					    '-cl_option' => '--createSparseFiles',
					    '-cl_alias' => '-s'),
				Option->new('-name' => 'blockSize',
					    '-cl_option' => '--blockSize',
					    '-default' => 512,
					    '-only_if' => '[createSparseFiles]',
					    '-pattern' => '\A\d+\Z'),
				Option->new('-name' => 'tmpdir',
					    '-cl_option' => '-T',
					    '-cl_alias' => '--tmpdir',
					    '-default' => $tmpdir)
				]);

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

my $linkWith = $CheckPar->getOptWithPar('linkWith');
@$linkWith = () unless $linkWith;
my $targetDir = $CheckPar->getOptWithPar('targetDir');
my $progressReport = $CheckPar->getOptWithPar('progressReport');
my $printDepth = $CheckPar->getOptWithoutPar('printDepth');
$printDepth = $printDepth ? 'yes' : 'no';
my $dontLinkSymlinks = $CheckPar->getOptWithoutPar('dontLinkSymlinks');
my $ignoreErrors = $CheckPar->getOptWithoutPar('ignoreErrors');
my (@sourceDir) = $CheckPar->getListPar();
my $saveRAM = $CheckPar->getOptWithoutPar('saveRAM');
my $createSparseFiles = $CheckPar->getOptWithoutPar('createSparseFiles');
my $blockSize = $CheckPar->getOptWithPar('blockSize');
$tmpdir = $CheckPar->getOptWithPar('tmpdir');

my $prLog;
my ($prLogKind) = ['A:BEGIN',
		   'Z:END',
		   'I:INFO',
		   'V:VERSION',
		   'W:WARNING',
		   'E:ERROR',
		   'S:STATISTIC',
		   'P:PROGRESS'];
$prLog = printLog->new('-kind' => $prLogKind,
		       '-tmpdir' => $tmpdir);

# check progressReport settings
my $progressDeltaTime = 0;
if ($progressReport)
{
    my ($count, $t);
    if ($progressReport =~ /,/)
    {
	($count, $t) = $progressReport =~ /\A(.*?),(.*)\Z/;
	$prLog->print('-kind' => 'E',
		      '-str' => ["wrong format for option progressReport " .
				 "time period <$t>"],
		      '-exit' => 1)
	    unless &dateTools::checkStr('-str' => $t);
	$progressDeltaTime = &dateTools::strToSec('-str' => $t);
    }
    else
    {
	$count = $progressReport;
    }
    $prLog->print('-kind' => 'E',
		  '-str' => ["counter <$count> for progress report " .
			     "must be a positive integer"],
		  '-exit' => 1)
	unless $count =~ /\A\d+\Z/;
    $progressReport = $count;
}
#print "progressReport=<$progressReport>, progressDeltaTime=<$progressDeltaTime>\n";

my (@lt) = (@$linkWith);
my (@lb) = (@sourceDir);
my $lts = $targetDir;
if (@lt)
{
    $prLog->print('-kind' => 'A',
		  '-str' =>
		  ["copy/link <" . join('><', @lb) . "> to <" .
		   join('><', @lt) . "> to <$lts>"]);
}
else
{
    $prLog->print('-kind' => 'A',
		  '-str' =>
		  ["copy/link <" . join('><', @lb) .
		   "> to <$lts>"]);
}
$prLog->print('-kind' => 'V',
	      '-str' => ["linkToDirs.pl, $main::STOREBACKUPVERSION"]);

# make paths absolute
my $i;
for ($i = 0 ; $i < @$linkWith ; $i++)
{
    my $p = $$linkWith[$i];
    $prLog->print('-kind' => 'E',
		  '-str' => ["--linkWith path <$p> not accessible"],
		  '-exit' => 1)
	unless -e $p;
    $$linkWith[$i] = &::absolutePath($p);
}
for ($i = 0 ; $i < @sourceDir ; $i++)
{
    my $p = $sourceDir[$i];
    $prLog->print('-kind' => 'E',
		  '-str' => ["sourceDir path <$p> not accessible"],
		  '-exit' => 1)
	unless -e $p;
    $sourceDir[$i] = &::absolutePath($p);
}
# remove doublicates (if any)
my (@tmp) = sort @$linkWith;
@$linkWith = ();
for ($i = 0 ; $i < @tmp ; $i++)
{
    push @$linkWith, $tmp[$i]
	if $i == 0 or $tmp[$i] ne $tmp[$i-1];
}
(@tmp) = @sourceDir;
@sourceDir = ();
for ($i = 0 ; $i < @tmp ; $i++)
{
    push @sourceDir, $tmp[$i]
	if $i == 0 or $tmp[$i] ne $tmp[$i-1];
}


# general checks
my $exit = 0;
{
    my ($devT) = (stat($targetDir))[0];
    foreach my $d (@$linkWith)
    {
	unless (-e $d)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["<$d> does not exist"]);
	    $exit = 1;
	}
	if (-l $d and not -d $d)   # is not a directory
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["<$d> is not a directory"]);
	    $exit = 1;
	}
 	my ($dev) = (stat($d))[0];
	if ($dev ne $devT)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["directory <$d> is not on the " .
			   "same device as <$targetDir> - " .
			  "setting hard links is not possible"]);
	    $exit = 1;
	}
	if ($tmpdir)
	{
	    unless (-d $tmpdir and -w $tmpdir)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["directory <$tmpdir> is not accessible"]);
		$exit = 1;
	    }
	}
   }
}
foreach my $d (@sourceDir)
{
    unless (-d $d)
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["<$d> is not a directory"]);
	$exit = 1;
    }
    if ((-l $d and not -d $d))   # is not a directory
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["<$d> is not a directory"]);
	$exit = 1;
    }
#print "----$d----$exit\n";
}
unless (-d $targetDir)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["<$targetDir> does not exist"]);
    $exit = 1;
}
if (-l $targetDir and not -d $targetDir)   # is not a directory
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["<$targetDir> is not a directory"]);
    $exit = 1;
}
foreach my $d (@sourceDir)
{
    my ($dir, $baseDir) = &::splitFileDir($d);
    if (-d "$targetDir/$baseDir")
    {
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["directory <$targetDir/$baseDir> already exists"]);
	$exit = 1 unless $ignoreErrors;
    }    
}
exit $exit if $exit;

# file for storing permissions of directories
my $tmpDirFile = &::uniqFileName("$tmpdir/linkTo.");
local *DIRFILE;
open(DIRFILE, '>', $tmpDirFile) or
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot open <$tmpDirFile>, exiting"],
		  '-add' => [__FILE__, __LINE__],
		  '-exit' => 1);
chmod 0600, $tmpDirFile;


my $indexDir = indexDir->new();

my (%inode2md5, %md52file);
my $inode2md5File = &::uniqFileName("$tmpdir/linkTo-inode2md5.");
my $md52fileFile = &::uniqFileName("$tmpdir/linkTo-md52file.");
if ($saveRAM)
{
    dbmopen(%inode2md5, $inode2md5File, 0600);
    dbmopen(%md52file, $md52fileFile, 0600);
}
my $stat = Statistic->new('-prLog' => $prLog,
			  '-progressReport' => $progressReport,
			  '-progressDeltaTime' => $progressDeltaTime);


#
# read all linkWith directores
#
my $rrd = recursiveReadDir->new('-dirs' => $linkWith,
				'-printDepth' => $printDepth,
				'-printDepthPrlogKind' => 'P',
				'-prLog' => $prLog);
$prLog->print('-kind' => 'I',
	      '-str' => ["start reading linkWith dirs <" .
			 join('> <', @$linkWith) . '>'])
    if @$linkWith;
my ($f, $t);
while (($f, $t) = $rrd->next())
{
#print "$t -> $f\n";

    if ($t eq 'f')     # normal file
    {
	$stat->incrRead();

	my ($dev, $inode, $mode, $uid, $gid, $size, $atime,
	    $mtime, $ctime) = (stat($f))[0,1,2,4,5,7,8,9,10];
	my $devInode = "$dev-$inode";

	next if exists $inode2md5{$devInode};  # already read

	my $md5 = &::calcMD5($f, $prLog);
	unless ($md5)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["could not calculate md5 sum of <$f>, skipping"]);
	    next;
	}
	$stat->incrMd5();
	my $md5size = "$md5-$size";
	$inode2md5{$devInode} = $md5size;

	my ($fbase, $fname, $index) = $indexDir->newFile($f);
	$md52file{$md5size} = "$index/$fname";
#print "\t$fbase, $fname, $index ($md5size)\n";
    }
    elsif ($t eq 'l')     # symbolic link
    {
	$stat->incrRead();
	
	my ($dev, $inode, $mode, $uid, $gid, $size, $atime,
	    $mtime, $ctime) = (lstat($f))[0,1,2,4,5,7,8,9,10];
	my $devInode = "$dev-$inode";

	next if exists $inode2md5{$devInode};  # already read

	my $md5 = &::readSymLinkCalcMd5($f, $prLog);
	unless ($md5)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["could not calculate md5 sum of symlink <$f>," .
			   " skipping"]);
	    next;
	}
	$stat->incrMd5();
	my $md5size = "L-$md5-$size";
	$inode2md5{$devInode} = $md5size;

	my ($fbase, $fname, $index) = $indexDir->newFile($f);
	$md52file{$md5size} = "$index/$fname";
#print "\tSymlink: $fbase, $fname, $index ($md5size)\n";
    }
}
#print "------------------------------------------\n";

$targetDir = &::absolutePath($targetDir);

#
# copy / link @sourceDir
#
$prLog->print('-kind' => 'I',
	      '-str' => ["start copying <" . join('> <', @sourceDir) . '>']);
foreach my $d (@sourceDir)
{
#print "---$d---\n";
    my ($dir, $baseDir) = &::splitFileDir($d);

    {
	my ($mode, $uid, $gid, $atime, $mtime) = (stat($d))[2,4,5,8,9];

	unless (mkdir "$targetDir/$baseDir", $mode)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["cannot create directory <$targetDir/$baseDir>"]);
	    exit 1 unless $ignoreErrors;
	}

	chown $uid, $gid, "$targetDir/$baseDir";
#	utime $atime, $mtime, "$targetDir/$baseDir";
	my $wr = "$targetDir/$baseDir";
	$wr =~ s/\n/\0/og;
	print DIRFILE "$atime $mtime $mode $wr\n";
	$stat->incrDir();
    }

    $rrd = recursiveReadDir->new('-dirs' => [$d],
				 '-printDepth' => $printDepth,
				 '-printDepthPrlogKind' => 'P',
				 '-prLog' => $prLog);
    while (($f, $t) = $rrd->next())
    {
	my $relPath = &::substractPath($f, $d);
	my $fnew = "$targetDir/$baseDir/$relPath";
#print "$t -> $f -> $fnew\n";

	my $linkSymlinks = 1;
	$linkSymlinks = 0
	    if ($t eq 'l' and $dontLinkSymlinks);
#print "linkSymlinks = $linkSymlinks\n";

	if ($t eq 'd')       # directory
	{
	    my ($mode, $uid, $gid, $atime, $mtime) =
		(stat($f))[2,4,5,8,9];
	    unless (mkdir $fnew)
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot create directory <$fnew>"]);
		exit 1 unless $ignoreErrors;
	    }
	    chown $uid, $gid, "$fnew";
	    my $wr = $fnew;
	    $wr =~ s/\n/\0/og;
	    print DIRFILE "$atime $mtime $mode $wr\n";
	    $stat->incrDir();
	}
	elsif ($t eq 'f' or $t eq 'l')  # normal file or symlink
	{
	    my ($dev, $inode, $mode, $uid, $gid, $size, $atime,
		$mtime, $ctime, $blocks);
	    if ($t eq 'f')
	    {
		($dev, $inode, $mode, $uid, $gid, $size, $atime,
		$mtime, $ctime, $blocks) = (stat($f))[0,1,2,4,5,7,8,9,10,12];
	    }
	    elsif ($t eq 'l')
	    {
		($dev, $inode, $mode, $uid, $gid, $size, $atime,
		$mtime, $ctime) = (lstat($f))[0,1,2,4,5,7,8,9,10];
	    }

	    my $devInode = "$dev-$inode";

	    if (exists $inode2md5{$devInode})  # hard link already read
	    {
		my $md5size = $inode2md5{$devInode};
		
		my $iFile = $md52file{$md5size};

		my $foundFile = $indexDir->replaceIndex($iFile);

#print "\tlink (1) $foundFile => $fnew\n";
		unless ($linkSymlinks and link $foundFile => $fnew)
		{
#print "\t\t!!!copy $f =>$fnew\n";
		    my ($fbase, $fname, $index) = $indexDir->newFile($fnew);
		    $md52file{$md5size} = "$index/$fname";

		    if ($t eq 'f')
		    {
#			unless (&::copyFile($f, $fnew, $prLog))
			unless (&::checkSparseAndCopyFiles(
				       $f, $fnew, $prLog, $size,
				       $blocks, $createSparseFiles,
				       $blockSize, $tmpdir))
			{
			    $prLog->print('-kind' => 'E',
					  '-str' =>
					  ["cannot copy <$f> to " .
					   "<$fnew>"]);
			    exit 1 unless $ignoreErrors;
			}
		    }
		    elsif ($t eq 'l')
		    {
			unless (&::copySymLink($f, $fnew))
			{
			    $prLog->print('-kind' => 'E',
					  '-str' =>
					  ["cannot copy symlink <$f> to " .
					   "<$fnew>"]);
			    exit 1 unless $ignoreErrors;
			}
		    }
		    $stat->incrCopy();
		}
		else
		{
		    $stat->incrLink();
		}
	    }
	    else     # cannot find same hard link
	    {
		my $md5size;
		if ($t eq 'f')
		{
		    my $md5 = &::calcMD5($f, $prLog);
		    unless ($md5)
		    {
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["could not calculate md5 sum of <$f>, skipping"]);
			next;
		    }
		    $md5size = "$md5-$size";
		}
		elsif ($t eq 'l')
		{
		    my $md5 = &::readSymLinkCalcMd5($f, $prLog);
		    unless ($md5)
		    {
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["could not calculate md5 sum of symlink <$f>," .
				       " skipping"]);
			next;
		    }
		    $md5size = "L-$md5-$size";
		}

		$stat->incrMd5();
		$inode2md5{$devInode} = $md5size;

		if (exists $md52file{$md5size})   # found same file
		{
		    my $iFile = $md52file{$md5size};
		    my $foundFile = $indexDir->replaceIndex($iFile);

#print "\tlink (2) $foundFile => $fnew\n";
		    unless ($linkSymlinks and link $foundFile => $fnew)
		    {
#print "\t\t!!!copy $f =>$fnew\n";
			my ($fbase, $fname, $index) = $indexDir->newFile($fnew);
			$md52file{$md5size} = "$index/$fname";

			if ($t eq 'f')
			{
#			    unless (&::copyFile($f, $fnew, $prLog))
			    unless (&::checkSparseAndCopyFiles(
					   $f, $fnew, $prLog, $size,
					   $blocks, $createSparseFiles,
					   $blockSize, $tmpdir))
			    {
				$prLog->print('-kind' => 'E',
					      '-str' =>
					      ["cannot copy <$f> to " .
					       "<$fnew>"]);
				exit 1 unless $ignoreErrors;
			    }
			}
			elsif ($t eq 'l')
			{
			    unless (&::copySymLink($f, $fnew))
			    {
				$prLog->print('-kind' => 'E',
					      '-str' =>
					      ["cannot copy symlink <$f> to " .
					       "<$fnew>"]);
				exit 1 unless $ignoreErrors;
			    }
			}
			$stat->incrCopy();
		    }
		    else
		    {
			$stat->incrLink();
		    }
		}
		else    # new file
		{
		    my ($fbase, $fname, $index) = $indexDir->newFile($fnew);
		    $md52file{$md5size} = "$index/$fname";

#print "\tcopy $f =>$fnew\n";
		    if ($t eq 'f')
		    {
#			unless (&::copyFile($f, $fnew, $prLog))
			unless (&::checkSparseAndCopyFiles(
				       $f, $fnew, $prLog, $size,
				       $blocks, $createSparseFiles,
				       $blockSize, $tmpdir))
			{
			    $prLog->print('-kind' => 'E',
					  '-str' =>
					  ["cannot copy <$f> to " .
					   "<$fnew>"]);
				exit 1 unless $ignoreErrors;
			    }
		    }
		    elsif ($t eq 'l')
		    {
			unless (&::copySymLink($f, $fnew))
			{
			    $prLog->print('-kind' => 'E',
					  '-str' =>
					  ["cannot copy symlink <$f> to " .
					   "<$fnew>"]);
				exit 1 unless $ignoreErrors;
			    }
		    }
		    $stat->incrCopy();
		}
	    }
	    if ($t eq 'l')      # symbolic link
	    {
		my $chown =
		    forkProc->new('-exec' => 'chown',
				  '-param' => ['-h', "$uid:$gid", $fnew],
				  '-outRandom' => "$tmpdir/chown-",
				  '-prLog' => $prLog);
		$chown->wait();
	    }
	    else
	    {
		chown $uid, $gid, $fnew;
		chmod $mode, $fnew;
		utime $atime, $mtime, $fnew;
	    }
	}
	else   # all file types except 'f' and 'd'
	{
	    &::copyDir($f, $fnew, "$tmpdir/stbuLink-", $prLog, $ignoreErrors);
	    $stat->incrCopy();
	}
    }
}

if ($saveRAM)
{
    dbmclose(%inode2md5);
    unlink $inode2md5File;
    dbmclose(%md52file);
    unlink $md52fileFile;
}

# set atime, mtime, mode of directories
close(DIRFILE);
unless (open(DIRFILE, '<', $tmpDirFile))
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot read <$tmpDirFile>, cannot set " .
			     "atime and mtime for directories"]);
}
else
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["setting atime, mtime of directories ..."]);

    my $line;
    while ($line = <DIRFILE>)
    {
	chop $line;
	my ($atime, $mtime, $mode, $df) = split(/\s/, $line, 4);
	$df =~ s/\0/\n/og;
	chmod $mode, $df;
	utime $atime, $mtime, $df;
	utime $atime, $mtime, $df;
    }
    close(DIRFILE);
}
unlink $tmpDirFile;


$stat->print();
if (@lt)
{
    $prLog->print('-kind' => 'Z',
		  '-str' =>
		  ["copy/link <" . join('><', @lb) . "> to <" .
		   join('><', @lt) . "> to <$lts>"]);
}
else
{
    $prLog->print('-kind' => 'Z',
		  '-str' =>
		  ["copy/link <" . join('><', @lb) .
		   "> to <$lts>"]);
}


exit 0;


##################################################
# retunrs 1 on success, 0 if copy fails
sub checkSparseAndCopyFiles
{
    my $source = shift;
    my $target = shift;
    my $prLog = shift;
    my $size = shift;
    my $blocks = shift;
    my $createSparseFiles = shift;
    my $blockSize = shift;
    my $tmpdir = shift;

    if ($createSparseFiles and  $blocks * $blockSize < $size) # maybe sparse file
    {
	my $ret = 1;   # success
	my $cp = forkProc->new('-exec' => 'cp',
			       '-param' =>
			       ["$source", "$target"],
			       '-outRandom' => "$tmpdir/linkTo-cp-",
			       '-prLog' => $prLog);
	$cp->wait();
	my $out = $cp->getSTDOUT();
	if (@$out)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' =>
			  ["copying of <$source> to <$target> reported:",
			   @$out]);
	}
	$out = $cp->getSTDERR();
	if (@$out)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
		  ["copying (with 'cp -r') of <$source> to <$target> reported:",
			   @$out]);
	    $ret = 0;
	}
	$prLog->print('-kind' => 'I',
		      '-str' => ["file <$source> copied as sparse file"])
	    if $ret;

	return $ret;
    }
    else
    {
	return &::copyFile($source, $target, $prLog);
    }
}



##################################################
package Statistic;

########################################
sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-prLog'             => undef,
		    '-progressReport'    => undef,
		    '-progressDeltaTime' => 0
		    );

    &::checkObjectParams(\%params, \@_, 'Statistic::new',
			 ['-prLog', '-progressReport']);
    &::setParamsDirect($self, \%params);

    $self->{'statCopy'} = 0;
    $self->{'statLink'} = 0;
    $self->{'statDir'} = 0;

    $self->{'statRead'} = 0;
    $self->{'statMd5'} = 0;

    $self->{'timeProgrReport'} =
	($self->{'progressDeltaTime'} > 0) ? time : 0;

    bless $self, $class;
}

########################################
sub incrCopy
{
    my $self = shift;

    ++$self->{'statCopy'};
    $self->checkProgress();
}

########################################
sub incrLink
{
    my $self = shift;

    ++$self->{'statLink'};
    $self->checkProgress();
}

########################################
sub incrDir
{
    my $self = shift;

    ++$self->{'statDir'};
    $self->checkProgress();
}

########################################
sub incrRead
{
    my $self = shift;

    ++$self->{'statRead'};
    $self->checkProgressRead();
}

########################################
sub incrMd5
{
    my $self = shift;

    ++$self->{'statMd5'};
}

########################################
sub checkProgressRead
{
    my $self = shift;

    my $n = $self->{'statRead'};
    if (($self->{'progressReport'} and
	$n % $self->{'progressReport'} == 0) or
	($self->{'timeProgrReport'} > 0 and
	 time >= $self->{'timeProgrReport'} + $self->{'progressDeltaTime'}))
    {
	$self->{'prLog'}->print('-kind' => 'P',
				'-str' =>
				["read $n items, calced " .
				$self->{'statMd5'} . " md5 sums"]);
	$self->{'timeProgrReport'} = time
	    if $self->{'timeProgrReport'} > 0;
    }
}

########################################
sub checkProgress
{
    my $self = shift;

    my $n = $self->{'statCopy'} + $self->{'statLink'} +
	$self->{'statDir'};
    if (($self->{'progressReport'} and
	 $n % $self->{'progressReport'} == 0) or
	($self->{'timeProgrReport'} > 0 and
	 time >= $self->{'timeProgrReport'} + $self->{'progressDeltaTime'}))
    {
	$self->{'prLog'}->print('-kind' => 'P',
				'-str' =>
				["processed $n items, calced " .
				$self->{'statMd5'} . " md5 sums; " .
				$self->{'statLink'} . " linked, " .
				$self->{'statCopy'} . " copied"]);
	$self->{'timeProgrReport'} = time
	    if $self->{'timeProgrReport'} > 0;
    }
}

########################################
sub print
{
    my $self = shift;

    $self->{'prLog'}->print('-kind' => 'S',
			    '-str' =>
			    ["read " .
			     $self->{'statRead'} . " items; created " .
			     $self->{'statDir'} . " dirs, " .
			     $self->{'statLink'} . " hard links, " .
			     $self->{'statCopy'} . " copied; calced " .
			     $self->{'statMd5'} . " md5 sums, "]);
}
