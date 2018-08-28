#! /usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2002-2014)
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
use Fcntl;
use Digest::MD5 qw(md5_hex);


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

require 'storeBackupGlob.pl';
require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'version.pl';
require 'fileDir.pl';
require 'forkProc.pl';
require 'storeBackupLib.pl';


my $md5CheckSumVersion = '1.1';
my $noRestoreParallel = 12;
my $checkSumFile = '.md5CheckSums';
my $exit = 0;

my $tmpdir = '/tmp';              # default value
$tmpdir = $ENV{'TMPDIR'} if defined $ENV{'TMPDIR'};

=head1 NAME

storeBackupRecover.pl - recovers files saved with storeBackup.pl.

=head1 SYNOPSIS

	storeBackupRecover.pl -r restore [-b root] -t targetDir [--flat]
		[-o] [--tmpdir] [--noHardLinks] [-p number] [-v] [-n]
		[--cpIsGnu] [--noGnuCp] [-s]

=head1 OPTIONS

=over 8

=item B<--restoreTree>, B<-r>

    file or (part of) the tree to restore
    when restoring a file, the file name in the backup has
    to be used (eg. with compression suffix)

=item B<--backupRoot>, B<-b>

    root of storeBackup tree, normally not needed

=item B<--targetDir>, B<-t>

    directory for unpacking

=item B<--flat>

    do not create subdirectories

=item B<--overwrite>, B<-o>

    overwrite existing files

=item B<--tmpdir>, B<-T>

    directory for temporary file, default is <$tmpdir>

=item B<--noHardLinks>

    do not reconstruct hard links in restore tree

=item B<--noRestoreParallel>, B<-p>

    max no of paralell programs to unpack, default is 12
    reduce this number if you are restoring blocked files
    and the system has insufficient RAM

=item B<--verbose>, B<-v>

    print verbose messages

=item B<--noRestored>, B<-n>

    print number of restored dirs, hardlinks, symlinks, files, ...

=item B<--noGnuCp>

    overwrite information in backup: you do not have gnucp
    installed
    (only relevant for sockets, block and character devices)

=item B<--createSparseFiles>, B<-s>

    creates sparse file from blocked files if full blockes
    are filled with zeros

=back

=head1 COPYRIGHT

Copyright (c) 2002-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'no',
		    '-list' => [Option->new('-name' => 'restoreTree',
					    '-cl_option' => '-r',
					    '-cl_alias' => '--restoreTree',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'backupRoot',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupRoot',
					    '-default' => ''),
				Option->new('-name' => 'targetDir',
					    '-cl_option' => '-t',
					    '-cl_alias' => '--targetDir',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'flat',
					    '-cl_option' => '--flat'),
				Option->new('-name' => 'overwrite',
					    '-cl_option' => '-o',
					    '-cl_alias' => '--overwrite'),
				Option->new('-name' => 'tmpDir',
					    '-cl_option' => '-T',
					    '-cl_alias' => '--tmpdir',
					    '-default' => $tmpdir),
				Option->new('-name' => 'noHardLinks',
					    '-cl_option' => '--noHardLinks'),
				Option->new('-name' => 'noRestoreParallel',
					    '-cl_option' => '-p',
					    '-cl_alias' => '--noRestoreParallel',
					    '-pattern' => '\A\d+\Z',
					    '-default' => $noRestoreParallel),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
				Option->new('-name' => 'noRestored',
					    '-cl_option' => '-n',
					    '-cl_alias' => '--noRestored'),
				Option->new('-name' => 'noGnuCp',
					    '-cl_option' => '--noGnuCp'),
				Option->new('-name' => 'createSparseFiles',
					    '-cl_option' => '--createSparseFiles',
					    '-cl_alias' => '-s')
				]
		    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

# Auswertung der Parameter
my $restoreTree = $CheckPar->getOptWithPar('restoreTree');
my $backupRoot = $CheckPar->getOptWithPar('backupRoot');
my $targetDir = $CheckPar->getOptWithPar('targetDir');
my $flat = $CheckPar->getOptWithoutPar('flat');
my $overwrite = $CheckPar->getOptWithoutPar('overwrite');
$tmpdir = $CheckPar->getOptWithPar('tmpDir');
my $noHardLinks = $CheckPar->getOptWithoutPar('noHardLinks');
my $noRestoreParallel = $CheckPar->getOptWithPar('noRestoreParallel');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $noRestored = $CheckPar->getOptWithoutPar('noRestored');
my $noGnuCp = $CheckPar->getOptWithoutPar('noGnuCp');
my $createSparseFiles = $CheckPar->getOptWithoutPar('createSparseFiles');


my $prLog = printLog->new('-kind' => ['I:INFO', 'W:WARNING', 'E:ERROR',
				      'S:STATISTIC', 'D:DEBUG', 'V:VERSION'],
			  '-tmpdir' => $tmpdir);
$prLog->fork($req);

$prLog->print('-kind' => 'E',
	      '-str' => ["target directory <$targetDir> does not exist"],
	      '-exit' => 1)
    unless (-d $targetDir);

$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupRecover.pl, $main::STOREBACKUPVERSION"])
    if $verbose;

eval "use DB_File";
if ($@)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["please install DB_File from " .
			     "CPAN for better performance"])
	if $verbose;
}

my $rt = $restoreTree;
my $restoreTree = &absolutePath($restoreTree);
$restoreTree = $1 if $restoreTree =~ /(.*)\/$/;  # remove trailing '/'

#
# md5CheckSum - Datei finden
$prLog->print('-kind' => 'E',
	      '-str' => ["directory or file <$rt> does not exist"],
	      '-exit' => 1)
    unless (-e $rt);
my $isFile = 1 if (-f $rt);

if ($backupRoot)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["directory <$backupRoot> does not exit"],
		  '-exit' => 1)
	unless (-d $backupRoot);
    $backupRoot = &absolutePath($backupRoot);
}
else
{
    my $dir = $restoreTree;
    $dir =~ s/(\/\.)*$//;      # remove trailing /.

    $backupRoot = undef;
    do
    {
	$dir =~ s/\/\.\//\//g;   # substitute /./ -> /

	# feststellen, ob eine .md5sum Datei vorhanden ist
	if (-f "$dir/$checkSumFile" or -f "$dir/$checkSumFile.bz2")
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["found info file <$checkSumFile> in " .
				     "directory <$dir>"])
		if ($verbose);
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["found info file <$checkSumFile> a second time in " .
			   "<$dir>, first time found in <$backupRoot>"],
			  '-exit' => 1)
		if ($backupRoot);

	    $backupRoot = $dir;
	}

	($dir, $_) = &splitFileDir($dir);
    } while ($dir ne '/');


    $prLog->print('-kind' => 'E',
		  '-str' => ["did not find info file <$checkSumFile>"],
		  '-exit' => 1)
	unless ($backupRoot);
}

$restoreTree = substr($restoreTree, length($backupRoot) + 1);


# ^^^
# $backupRoot beinhaltet jetzt den Pfad zum Archiv
# $restoreTree beinhaltet jetzt den relativen Pfad innerhalb des Archivs

$prLog->print('-kind' => 'E',
	      '-str' => ["cannot restore <$backupRoot> because of unresolved links",
	      "run storeBackupUpdateBackup.pl to resolve"],
	      '-exit' => 1)
    if -e "$backupRoot/.storeBackupLinks/linkFile.bz2";

my (%setPermDirs);
unless ($flat)
{
    # Subtree unter dem Zieldirectory erzeugen
    &::makeFilePath("$targetDir/$restoreTree", $prLog);

    my (@d) = split(/\/+/, $restoreTree);
    my $i;
    for ($i = 0 ; $i < @d ; $i++)
    {
	$setPermDirs{join('/', @d[0..$i])} = 1;
    }
}

#
# Jezt Infofile einlesen und die gewünschten Dateien aussortieren
#

my $rcsf = readCheckSumFile->new('-checkSumFile' =>
				 "$backupRoot/$checkSumFile",
				 '-prLog' => $prLog,
				 '-tmpdir' => $tmpdir);

my $fork = parallelFork->new('-maxParallel' => $noRestoreParallel,
			     '-prLog' => $prLog);

my ($uncompr, @uncomprPar) = @{$rcsf->getInfoWithPar('uncompress')};
my ($cp, @cpPar) = ('cp', '-dPR');
my $postfix = $rcsf->getInfoWithPar('postfix');
my $gnucp = $rcsf->getInfoWithPar('cpIsGnu');
$gnucp = ($gnucp eq 'yes') ? 1 : 0;
$gnucp = 0 if $noGnuCp;
my $archiveTypes = $rcsf->getInfoWithPar('archiveTypes');
my $specialTypeArchiver = $rcsf->getInfoWithPar('specialTypeArchiver');

$main::IOCompressDirect = 0;
if ($uncompr eq 'bzip2' or $uncompr eq 'bunzip2')
{
    eval "use IO::Uncompress::Bunzip2 qw(bunzip2)";
    if ($@)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["please install IO::Uncompress::Bunzip2 from " .
				 "CPAN for better performance"]);
    }
    else
    {
	$main::IOCompressDirect = 1;
    }
}

# dbm-File öffnen
my %DBMHardLink;        # key: dev-inode (oder undef), value: filename
my %hasToBeLinked = (); # hier werden die zu linkenden Dateien gesammelt,
                        # bis die Referenzdatei vollständig zurückgesichert ist
unless ($noHardLinks)
{
    dbmopen(%DBMHardLink, "$tmpdir/stbrecover.$$", 0600);
}

my $noFilesCopy = 0;
my $noFilesCompr = 0;
my $noFilesBlocked = 0;
my $noSymLinks = 0;
my $noNamedPipes = 0;
my $noSockets = 0;
my $noBlockDevs = 0;
my $noCharDevs = 0;
my $noDirs = 0;
my $hardLinks = 0;

$restoreTree = '' if $restoreTree eq '.';
my $lrestoreTree = length($restoreTree);

my $tmpDirFile = &::uniqFileName("$tmpdir/stbuRec.");
&::checkDelSymLink($tmpDirFile, $prLog, 0x01);
local *DIRFILE;
open(DIRFILE, '>', $tmpDirFile) or
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot open <$tmpDirFile>, exiting"],
		  '-add' => [__FILE__, __LINE__],
		  '-exit' => 1);
chmod 0600, $tmpDirFile;

my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
    $size, $uid, $gid, $mode, $filename);
#print "restoreTree = <$restoreTree>\n";
#print "lrestoreTree = <$lrestoreTree>\n";
#print "isFile = <$isFile>\n";
while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	 $size, $uid, $gid, $mode, $filename) = $rcsf->nextLine()) > 0)
{
    my $f = $filename;
    if (exists($setPermDirs{$f}))
    {
	chown $uid, $gid, "$targetDir/$f";
	chmod $mode, "$targetDir/$f";
	utime $atime, $mtime, "$targetDir/$f";
    }
    if ($isFile and length($md5sum) == 32)
    {
	$f .= $postfix if ($compr eq 'c');
    }
#print "from .md5CheckSums: <$f> <$restoreTree> $lrestoreTree\n";
    if ($restoreTree eq ''
	or "$restoreTree/" eq substr("$f/", 0, $lrestoreTree + 1)
	or ($isFile and $restoreTree eq $f))
    {
#print "---> restore!\n";
	my $targetFile;
	if ($flat)
	{
	    ($_, $targetFile) = &splitFileDir($filename);
	    $targetFile = "$targetDir/$targetFile";
	}
	else
	{
	    $targetFile = "$targetDir/$filename";
	}
	$targetFile =~ s/\/+/\//g;        # // -> /

	if (not $overwrite and -e $targetFile)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' => ["target $targetFile already exists"]);
	    next;
	}

	my $useGnuCp = $gnucp and ($md5sum eq 'socket' or
				   $md5sum eq 'blockdev' or
				   $md5sum eq 'chardev');

	if ($md5sum eq 'dir')
	{
	    if (not $flat and not -e $targetFile)
	    {
		++$noDirs;
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["cannot create directory <$targetFile>"],
			      '-exit' => 1)
		    unless mkdir $targetFile;
		chown $uid, $gid, $targetFile;
#		chmod $mode, $targetFile;
#		utime $atime, $mtime, $targetFile;

		my $wr = $targetFile;
		$wr =~ s/\n/\0/og;
		print DIRFILE "$atime $mtime $mode $wr\n";

		$prLog->print('-kind' => 'I',
			      '-str' => ["mkdir $targetFile"])
		    if ($verbose);
	    }
	}
	elsif ($md5sum eq 'symlink')
	{
	    unless ($noHardLinks)
	    {
		if (defined($DBMHardLink{$devInode}))   # muss nur gelinkt werden
		{
		    if (link $DBMHardLink{$devInode}, $targetFile)
		    {
			$prLog->print('-kind' => 'I',
				      '-str' =>
				      ["link " . $DBMHardLink{$devInode} .
				       " $targetFile"])
			    if $verbose;
#			utime $atime, $mtime, $f;
			++$hardLinks;
		    }
		    else
		    {
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["failed: link " .
				       $DBMHardLink{$devInode} .
				       " $targetFile"]);
			$exit = 1;
		    }
		    goto contLoop;
		}
		else
		{
		    $DBMHardLink{$devInode} = $targetFile;
		}
	    }
	    my $linkTo = readlink "$backupRoot/$filename";

	    ++$noSymLinks;
	    symlink $linkTo, $targetFile;

	    # bei einigen Betriebssystem (z.B. Linux) wird bei Aufruf
	    # des Systemcalls chmod bei symlinks nicht der Symlink selbst
	    # geaendert, sondern die Datei, auf die er verweist.
	    # (dann muss lchown genommen werden -> Inkompatibilitaeten!?)
	    my $chown = forkProc->new('-exec' => 'chown',
				      '-param' => ['-h', "$uid:$gid",
						   "$targetFile"],
				      '-outRandom' => "$tmpdir/chown-",
				      '-prLog' => $prLog);
	    $chown->wait();
#	    utime $atime, $mtime, $targetFile;
	    $prLog->print('-kind' => 'I',
			  '-str' => ["ln -s $linkTo $targetFile"])
		if ($verbose);
	}
	elsif ($md5sum eq 'pipe')
	{
	    if ($specialTypeArchiver and
		$archiveTypes =~ /p/)
	    {
		&::extractFileFromArchive($filename, $targetDir, $backupRoot,
		    $specialTypeArchiver, $prLog, $tmpdir);
		$prLog->print('-kind' => 'I',
			      '-str' =>
	     ["$specialTypeArchiver $backupRoot/$filename -> $targetFile"])
		    if ($verbose);
	    }
	    else
	    {
		my $mknod = forkProc->new('-exec' => 'mknod',
					  '-param' => ["$targetFile", 'p'],
					  '-outRandom' => "$tmpdir/mknod-",
					  '-prLog' => $prLog);
		$mknod->wait();
		my $out = $mknod->getSTDOUT();
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["STDOUT of <mknod $targetFile p>:", @$out])
		    if (@$out > 0);
		$out = $mknod->getSTDERR();
		if (@$out > 0)
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["STDERR of <mknod $targetFile p>:", @$out]);
			$exit = 1;
		}
		chown $uid, $gid, $targetFile;
		chmod $mode, $targetFile;
		utime $atime, $mtime, $targetFile;
		$prLog->print('-kind' => 'I',
			      '-str' =>
			      ["mknod $targetFile p"])
		    if ($verbose);

	    }
	}
	elsif (length($md5sum) == 32 or            # normal file
	       $useGnuCp or $specialTypeArchiver)  # special file
	{
# Idee zur Lösung des parallelitäts-Problems beim Zurücksichern
# in Verbindung mit dem Setzen der hard links:
# erste Datei:
# dev-inode => '.' in dbm-file (%DBMHardLink)
# fork->add_block
# wenn fertig, dann dev-inode => filename in dbm-file
#
# zweite Datei (hard link)
# nachsehen in dbm-file
# wenn '.' -> in Warteschlange hängen (hash)
# wenn filename -> linken
# unten immer Warteschlange in dbm-file überprüfen
	    my ($old, $new) = (undef, undef);

	    unless ($noHardLinks) # Hard Link überprüfen
	    {
		if (defined($DBMHardLink{$devInode}))   # muss nur gelinkt werden
		{
		    $hasToBeLinked{$targetFile} = [$devInode, $uid, $gid, $mode,
						   $atime, $mtime];
		    $hardLinks++;
		    goto contLoop;
		}
		else
		{
		    $DBMHardLink{$devInode} = '.';   # ist in Bearbeitung
		}
	    }
	    if ($compr eq 'u')    # was not compressed, also valid for socket,
	    {                     # blockdev, chardev
		if (not $overwrite and -e $targetFile)
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["target $targetFile already exists:",
				   "\t$cp @cpPar $backupRoot/$filename " .
				   "$targetFile"]);
		}
		else
		{
		    $noFilesCopy++ unless $useGnuCp;
		    $noSockets++ if $md5sum eq 'socket';
		    $noBlockDevs++ if $md5sum eq 'blockdev';
		    $noCharDevs++ if $md5sum eq 'chardev';

		    if ($specialTypeArchiver and
			$archiveTypes =~ /[Sbc]/)
		    {
			&::extractFileFromArchive($filename, $targetDir, $backupRoot,
						  $specialTypeArchiver, $prLog,
						  $tmpdir);

			$prLog->print('-kind' => 'I',
				      '-str' =>
		      ["$specialTypeArchiver $backupRoot/$filename -> $targetFile"])
			    if ($verbose);
		    }
		    else
		    {
			my $par = [@cpPar, "$backupRoot/$filename", "$targetFile"];
			($old, $new) =
			    $fork->add_block('-exec' => $cp,
					     '-param' => $par,
					     '-outRandom' => "$tmpdir/recover-",
					     '-info' => [$targetFile, $uid, $gid, $mode,
							 $atime, $mtime, $devInode,
							 [$cp, @$par]]);
			$prLog->print('-kind' => 'I',
				      '-str' =>
				      ["cp $backupRoot/$filename $targetFile"])
			    if ($verbose);
		    }
		}
	    }
	    elsif ($compr eq 'c')          # war komprimiert
	    {
		if (not $overwrite and -e $targetFile)
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["target $targetFile already exists:",
				   "\t$uncompr @uncomprPar " .
				   "< $backupRoot/$filename$postfix " .
				   "> $targetFile"]);
		}
		else
		{
		    ++$noFilesCompr;
		    my $comm = [$uncompr, @uncomprPar, '<',
				"$backupRoot/$filename$postfix", '>',
				$targetFile];
		    ($old, $new) =
			$fork->add_block('-exec' => $uncompr,
				   '-param' => \@uncomprPar,
				   '-stdin' => "$backupRoot/$filename$postfix",
				   '-stdout' => "$targetFile",
				   '-delStdout' => 'no',
				   '-outRandom' => "$tmpdir/recover-",
				   '-info' => [$targetFile, $uid, $gid, $mode,
					       $atime, $mtime, $devInode, $comm]);
		    $prLog->print('-kind' => 'I',
				  '-str' => ["$uncompr @uncomprPar < " .
					     "$backupRoot/$filename$postfix > " .
					     "$targetFile"])
			if ($verbose);
		}
	    }
	    elsif ($compr eq 'b')       # blocked file
	    {
		++$noFilesBlocked;
		my $comm = ["cp (block", "$backupRoot/$filename$postfix",
			    "$targetFile"];
		($old, $new) =
		    $fork->add_block('-function' => \&uncompressCatBlock,
				     '-funcPar' => ["$backupRoot/$filename",
				     $backupRoot, $createSparseFiles,
				     $targetFile, '\A\d.*', $uncompr, \@uncomprPar,
				     $postfix, $size, $prLog],
				     '-info' => [$targetFile, $uid, $gid, $mode,
						 $atime, $mtime, $devInode, $comm]);
		$prLog->print('-kind' => 'I',
			      '-str' => ["cp (blocked) " .
					     "$backupRoot/$filename$postfix " .
					     "$targetFile"])
			if ($verbose);
	    }
	    else
	    {
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["unknow compr flag <$compr> in .md5CheckSums " .
			       "for file <$backupRoot/$filename>"]);
		$exit = 1;
	    }
	    if ($old)
	    {
		my ($f, $oUid, $oGid, $oMode, $oAtime, $oMtime, $oDevInode) =
		    @{$old->get('-what' => 'info')};
		unless ($noHardLinks)
		{                                 # File in DBM vermerken
		    $DBMHardLink{$oDevInode} = $f;
		}
		chown $oUid, $oGid, $f;
		chmod $oMode, $f;
		utime $oAtime, $oMtime, $f;
	    }

	    goto finish if $isFile;    # aufhören, ist nur _eine_ Datei
	}
	else    # unknown type
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["unknown entry <$md5sum> for file <$filename>:"]);
	    $exit = 1;
	}
    }

contLoop:;
# nachsehen, ob offene Links gesetzt werden können
    &setHardLinks(\%hasToBeLinked, \%DBMHardLink, $prLog, $verbose)
	unless $noHardLinks;

}

finish:;

my $job;
while ($job = $fork->waitForAllJobs())
{
    my ($f, $oUid, $oGid, $oMode, $oAtime, $oMtime, $oDevInode, $comm) =
	@{$job->get('-what' => 'info')};

    if (ref($job) eq 'forkProc')
    {
	my $out = $job->getSTDERR();
	if (@$out > 0)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["STDERR of: @$comm", @$out]);
	    $exit = 1;
	}
	if ($job->get('-what' => 'status'))
	{
	    $exit = 1;
	}
    }

    unless ($noHardLinks)
    {                                 # File in DBM vermerken
	$DBMHardLink{$oDevInode} = $f;
    }
    chown $oUid, $oGid, $f;
    chmod $oMode, $f;
    utime $oAtime, $oMtime, $f
}

unless ($noHardLinks)
{
    &setHardLinks(\%hasToBeLinked, \%DBMHardLink, $prLog, $verbose);
    dbmclose(%DBMHardLink);
    unlink "$tmpdir/stbrecover.$$";
}

# set atime, mtime, mode of directories
close(DIRFILE);
unless (open(DIRFILE, '<', $tmpDirFile))
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot read <$tmpDirFile>, cannot set " .
			     "atime and mtime for directories"]);
    $exit = 1;
}
else
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["setting atime, mtime of directories ..."])
	if $verbose;

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

$prLog->print('-kind' => 'I',
	      '-str' =>
	      [join(', ',
		    ($noDirs ? "$noDirs dirs" : ()),
		    ($hardLinks ? "$hardLinks hardlinks" : ()),
		    ($noSymLinks ? "$noSymLinks symlinks" : ()),
		    ($noNamedPipes ? "$noNamedPipes named pipes" : ()),
		    ($noSockets ? "$noSockets sockets" : ()),
		    ($noBlockDevs ? "$noBlockDevs block devs" : ()),
		    ($noCharDevs ? "$noCharDevs char devs" : ()),
		    ($noFilesCopy ? "$noFilesCopy copied" : ()),
		    ($noFilesCompr ? "$noFilesCompr uncompressed" : ()),
		    ($noFilesBlocked ? "$noFilesBlocked cat blocked files" : ()))]
    )
    if ($noRestored);

exit $exit;


############################################################
sub setHardLinks
{
    my ($hasToBeLinked, $DBMHardLink, $prLog, $verbose) = @_;

    my $f;
    foreach $f (keys %$hasToBeLinked)
    {
	my ($di, $uid, $gid, $mode, $atime, $mtime) = @{$$hasToBeLinked{$f}};
	if (defined($$DBMHardLink{$di}) and $$DBMHardLink{$di} ne '.')
	{
	    my $oldF = $$DBMHardLink{$di};
	    if (-e $f)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["cannot link <$f> to itself"]);
	    }
	    else
	    {		
		if (link $oldF, $f)
		{
		    $prLog->print('-kind' => 'I',
				  '-str' => ["link $oldF $f"])
			if ($verbose);
		    chown $uid, $gid, $f;
		    chmod $mode, $f;
		    utime $atime, $mtime, $f;
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["failed: link $oldF $f"]);
		}
	    }
	    delete $$hasToBeLinked{$f};
	}
    }
}


########################################
sub uncompressCatBlock
{
    my $fromDir = shift;
    my $backupRoot = shift;
    my $createSparseFiles = shift;
    my $toFile = shift;
    my $mask = shift;
    my $umcompr = shift;
    my $uncomprPar = shift;
    my $postfix = shift;
    my $size = shift;
    my $prLog = shift;

    my $nBlocks = 0;
    my (@entries, @md5, @compr);

    my $fileIn =
	pipeFromFork->new('-exec' => 'bzip2',
			  '-param' => ['-d'],
			  '-stdin' => "$fromDir/.md5BlockCheckSums.bz2",
			  '-outRandom' => "$tmpdir/stbuPipeFrom11-",
			  '-prLog' => $prLog);
    my $l;
    while ($l = $fileIn->read())
    {
	my ($l_md5, $l_compr, $l_f, $n);
	chomp $l;
	$n = ($l_md5, $l_compr, $l_f) = split(/\s/, $l, 3);
	if ($n != 3)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["strange line in <$fromDir/.md5BlockCheckSums.bz2> " .
			   "in line " . $fileIn->get('-what' => 'lineNr') .
			   ":", "\t<$l>"]);
	    return 1;
	}
	++$nBlocks;
	push @md5, $l_md5;
	push @compr, $l_compr;
	push @entries, $l_f;
    }
    $fileIn->close();
    $fileIn = undef;

    &::createSparseFile($toFile, $size, $prLog) or exit 1;

    my $md5null = '';

    my $ret = 0;
    local *TO;
    unless (sysopen(TO, $toFile, O_CREAT | O_WRONLY))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot write to <$toFile>"]);
	$ret = 1;
    }

    my $blockSize = 0;
    for (my $iBlock = 0 ; $iBlock < @entries ; ++$iBlock)
    {
	my $entry = $entries[$iBlock];
	my $md5 = $md5[$iBlock];
	my $compr = $compr[$iBlock];
	my $actSeekPos = $blockSize * $iBlock;

	sysseek(TO, $actSeekPos, 0);

	next if ($md5 eq $md5null);

	my $buffer;
	local *FROM;
	my $fileIn = undef;
	if ($compr eq 'c')       # compressed block
	{
	    if ($main::IOCompressDirect)
	    {
		my $input = "$backupRoot/$entry";
		my $uc = new IO::Uncompress::Bunzip2 $input;
		while ($uc->read($buffer, 10*1024**2))
		{
		    my $n;
		    unless ($n = syswrite(TO, $buffer))
		    {
			$prLog->print('-kind' => 'E',
				      '-str' => ["writing to <$toFile> failed"]);
			$ret = 1;
		    }
		    $blockSize += $n if $iBlock == 0;
		}
	    }
	    else
	    {
		$fileIn =
		    pipeFromFork->new('-exec' => $uncompr,
				      '-param' => \@uncomprPar,
				      '-stdin' => "$backupRoot/$entry",
				      '-outRandom' => "$tmpdir/stbuPipeFrom11-",
				      '-prLog' => $prLog);
		while ($fileIn->sysread(\$buffer, 10*1024**2))
		{
		    my $n;
		    unless ($n = syswrite(TO, $buffer))
		    {
			$prLog->print('-kind' => 'E',
				      '-str' => ["writing to <$toFile> failed"]);
			$ret = 1;
		    }
		    $blockSize += $n if $iBlock == 0;
		}
	    }
	}
	else           # block not compressed
	{
	    unless (sysopen(FROM, "$backupRoot/$entry", O_RDONLY))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot read <$backupRoot/$entry>"]);
		return 1;
	    }
	    while (sysread(FROM, $buffer, 10*1024**2))
	    {
		my $n;
		unless ($n = syswrite(TO, $buffer))
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["writing to <$toFile> failed"]);
		    $ret = 1;
		}
		$blockSize += $n if $iBlock == 0;
	    }
	}

	if ($fileIn)
	{
	    $fileIn->close();
	    $fileIn = undef;
	}
	else
	{
	    close(FROM);
	}

	if ($iBlock == 0)
	{
	    $md5null = &::calcMD5null($blockSize)
		if $createSparseFiles;
	}
    }
    close(TO);
    return $ret;
}


############################################################
# calc md5 sum of block with $size time zero
sub calcMD5null
{
    my $size = shift;

    my $null = pack('C', 0) x $size;

    my $md5 = Digest::MD5->new();
    $md5->add($null);
    return $md5->hexdigest();
}
