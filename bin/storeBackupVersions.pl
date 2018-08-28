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

use Fcntl qw(O_RDWR O_CREAT);
use File::Copy;
use POSIX;
use Digest::MD5 qw(md5_hex);

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
require 'storeBackupLib.pl';

my $checkSumFile = '.md5CheckSums';

=head1 NAME

storeBackupVersions.pl - locates different versions of a file saved with storeBackup.pl.

=head1 SYNOPSIS

	storeBackupVersions.pl -f file [-b root]  [-v]
	 [-l [-a | [-s] [-u] [-g] [-M] [-c] [-m]]]

=head1 OPTIONS

=over 8

=item B<--file>, B<-f>

    file name (name in the backup, probably with suffix
    from compression)

=item B<--backupRoot> B<-b>

    root of storeBackup tree, normally not needed

=item B<--verbose>, B<-v>

    print verbose messages

=item B<--locateSame>, B<-l>

    locate same file with other names

=item B<--showAll>, B<-A>

    same as: [-s -u -g -M -c -m]

=item B<--size>, B<-s>

    show size (human readable) of source file

=item B<--uid>, B<-u>

    show uid of source file

=item B<--gid>, B<-g>

    show gid of source file

=item B<--mode>, B<-M>

    show permissions of source file

=item B<--ctime>, B<-c>

    show creation time of source file

=item B<--mtime>, B<-m>

    show modify time of source file

=item B<--atime>, B<-a>

    show access time of source file

=back

It does not always work correctly when a file is saved blocked *and*
non-blocked in different backups. In such cases, use option B<--locateSame>.

=head1 COPYRIGHT

Copyright (c) 2002-2014 by Heinz-Josef Claes (see README)
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'no',
		    '-list' => [Option->new('-name' => 'file',
					    '-cl_option' => '-f',
					    '-cl_alias' => '--file',
					    '-param' => 'yes',
					    '-must_be' => 'yes'),
				Option->new('-name' => 'backupRoot',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupRoot',
					    '-default' => ''),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
				Option->new('-name' => 'locateSame',
					    '-cl_option' => '-l',
					    '-cl_alias' => '--locateSame'),
				Option->new('-name' => 'showAll',
					    '-cl_option' => '-A',
					    '-cl_alias' => '--showAll',
					    '-only_if' => '[locateSame]',
					    '-comment' =>
				"-s can only be use in conjunction with -l\n"),
				Option->new('-name' => 'size',
					    '-cl_option' => '-s',
					    '-cl_alias' => '--size',
					    '-only_if' =>
					    '[locateSame] and not [showAll]'),
				Option->new('-name' => 'uid',
					    '-cl_option' => '-u',
					    '-cl_alias' => '--uid',
					    '-only_if' =>
					    '[locateSame] and not [showAll]'),
				Option->new('-name' => 'gid',
					    '-cl_option' => '-g',
					    '-cl_alias' => '--gid',
					    '-only_if' =>
					    '[locateSame] and not [showAll]'),
				Option->new('-name' => 'mode',
					    '-cl_option' => '-M',
					    '-cl_alias' => '--mode',
					    '-only_if' =>
					    '[locateSame] and not [showAll]'),
				Option->new('-name' => 'ctime',
					    '-cl_option' => '-c',
					    '-cl_alias' => '--ctime',
					    '-only_if' =>
					    '[locateSame] and not [showAll]'),
				Option->new('-name' => 'mtime',
					    '-cl_option' => '-m',
					    '-cl_alias' => '--mtime',
					    '-only_if' =>
					    '[locateSame] and not [showAll]'),
				Option->new('-name' => 'atime',
					    '-cl_option' => '-a',
					    '-cl_alias' => '--atime',
					    '-only_if' =>
					    '[locateSame] and not [showAll]')
				]
		    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

# Auswertung der Parameter
my $file = $CheckPar->getOptWithPar('file');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $backupRoot = $CheckPar->getOptWithPar('backupRoot');
my $locateSame = $CheckPar->getOptWithoutPar('locateSame');
my $showAll = $CheckPar->getOptWithoutPar('showAll');
my $showSize = $CheckPar->getOptWithoutPar('size') | $showAll;
my $showUID = $CheckPar->getOptWithoutPar('uid') | $showAll;
my $showGID = $CheckPar->getOptWithoutPar('gid') | $showAll;
my $showMode = $CheckPar->getOptWithoutPar('mode') | $showAll;
my $showCTime = $CheckPar->getOptWithoutPar('ctime') | $showAll;
my $showMTime = $CheckPar->getOptWithoutPar('mtime') | $showAll;
my $showATime = $CheckPar->getOptWithoutPar('atime') | $showAll;

my $f = $file;
my $file = &absolutePath($file);

my $prLog = printLog->new('-kind' => ['I:INFO', 'W:WARNING', 'E:ERROR',
				      'S:STATISTIC', 'D:DEBUG', 'V:VERSION']);

$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupVersions.pl, $main::STOREBACKUPVERSION"])
    if $verbose;

#
# md5CheckSum - Datei finden
$prLog->print('-kind' => 'E',
	      '-str' => ["file <$f> does not exist"],
	      '-exit' => 1)
    unless (-f $f or -d $f);

if ($backupRoot)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["directory <$backupRoot> does not exist"],
		  '-exit' => 1)
	unless (-d $backupRoot);
    $backupRoot = &absolutePath($backupRoot);
}
else
{
    my ($dir, $x) = &splitFileDir($file);
    $backupRoot = undef;
    do
    {
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

	($dir, $x) = &splitFileDir($dir);
    } while ($dir ne '/');

    $prLog->print('-kind' => 'E',
		  '-str' => ["did not find info file <$checkSumFile>"],
		  '-exit' => 1)
	unless ($backupRoot);
}

my $checkSumFileRoot = $checkSumFile;
$checkSumFileRoot .= ".bz2" if (-f "$backupRoot/$checkSumFile.bz2");
$prLog->print('-kind' => 'E',
	      '-str' => ["no info file <$checkSumFileRoot> in <$backupRoot>"],
	      '-exit' => 1)
    unless(-f "$backupRoot/$checkSumFileRoot");

# jetzt $restoreTree relativ zu $backupRoot machen
my $fileWithRelPath = substr($file, length($backupRoot) + 1);
my ($storeBackupAllTrees, $fileDateDir) = &splitFileDir($backupRoot);

# ^^^
# Beispiel:            (/tmp/stbu/2001.12.20_16.21.59/perl/Julian.c.bz2)
# $backupRoot beinhaltet jetzt den Pfad zum Archiv
#                      (/tmp/stbu/2001.12.20_16.21.59)
# $file beinhaltet die Datei mit kompletten, absoluten Pfad
#                      (/tmp/stbu/2001.12.20_16.21.59/perl/Julian.c.bz2)
# $fileWithRelPath beinhaltet jetzt den relativen Pfad innerhalb des Archivs
#                      (perl/Julian.c.bz2)
# $storeBackupAllTrees beinhaltet den Root-Pfad des storeBackup (oberhalb
#      der Datum Directories)
#                      (/tmp/stbu)
# $fileDateDir beinhaltet den Namen des Datum-Dirs des gesuchten files
#                      (2001.12.20_16.21.59)

#print "backupRoot = $backupRoot\n";
#print "file = $file\n";
#print "fileWithRelPath = $fileWithRelPath\n";
#print "storeBackupAllTrees = $storeBackupAllTrees\n";
#print "fileDateDir = $fileDateDir\n\n";


$prLog->print('-kind' => 'I',
	      '-str' => ["checking for <$fileWithRelPath>"])
    if $verbose;

# Versions-Directories unter $backupRoot einlesen
my (@allDirs) = (&::readAllBackupDirs($storeBackupAllTrees, $prLog, 1));
#print "allDirs =\n", join("\n", @allDirs), "\n";

# check for lateLinks
my (%linkFile);
my ($d, @d);
foreach $d (@allDirs)
{
    if (-e "$d/.storeBackupLinks/linkFile.bz2")
    {
	push @d, "  $d";
	$linkFile{$d} = 1;
    }
}
$prLog->print('-kind' => 'W',
	      '-str' => ["found unresolved links in : ",
			 @d,
			 "please run storeBackupUpdateBackup.pl",
			 "generated list will not be complete!",
			 ""])
    if @d;


# Zuerst die Dateien direkt auf Existenz überprüfen
# dann md5-Summen berechnen, um unterschiedliche Stände festzustellen
my (@files, @md5sum, @dirs, $entry);
my $md5sumBlock = undef;
my $lastInode = undef;
foreach $entry (@allDirs)
{
    if (exists $linkFile{$entry})
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["skipping <$entry>"]);
	next;
    }

    my $f = $entry . '/' . $fileWithRelPath;
    if (-f $f)
    {
	push @files, $f;
	push @dirs, $entry;

	# erst mal prüfen, ob inode identisch ist
	my ($inode, $size) = (stat($f))[1,7];
	if ($inode == $lastInode)
	{
	    push @md5sum, $md5sum[@md5sum - 1];  # letzte md5 Summe kopieren
	    next;              # md5 Summe muss nicht berechnet werden
	}
	$lastInode = $inode;

	# md5 Summe muss berechnet werden
	my $md5 = &::calcFileMD5Sum("$f");
	$prLog->print('-kind' => 'E',
		      '-str' => ["could not read <$f>"])
	    unless $md5;

	push @md5sum, $md5;
    }
    elsif (-d $f)       # blocked file
    {
	# md5 sum of block check sum file
	my $fBlock = "$f/.md5BlockCheckSums.bz2";
	unless (-f $fBlock)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open <$fBlock>"]);
	    next;
	}
	my $md5 = &::calcFileMD5Sum("$fBlock");
	$prLog->print('-kind' => 'E',
		      '-str' => ["could not read <$fBlock>"])
	    unless $md5;
	push @files, $f;
	push @dirs, $entry;
	push @md5sum, $md5;
    }
}

#print "files = \n", join("\n", @files), "\n";
#print "md5s = \n", join("\n", @md5sum), "\n";

# Unterschiedliche Versionen merken
my ($i, $j);
my (@versionFiles) = $files[0];
my (@versionDirs) = $dirs[0];
my $lastmd5 = $md5sum[0];
printf("%2d %s\n", 1, $versionFiles[0]) unless $locateSame;
for ($j = 0, $i = 1 ; $i < @files ; $i++)
{
    if ($md5sum[$i] ne $lastmd5)
    {
	$lastmd5 = $md5sum[$i];
	++$j;
	$versionFiles[$j] = $files[$i];
	$versionDirs[$j] = $dirs[$i];
	printf("%2d %s\n", $j + 1, $versionFiles[$j]) unless $locateSame;
    }
}

exit 0 unless $locateSame;

my %versionMD5sum;  # md5 Summen müssen aus $checkSumFile gelesen werden,
                    # da ansonsten komprimierte Dateien mit nicht-komprimierten
                    # verglichen würden!
my %versionSize;    # key = md5sum (wie oben), value = size aus $checkSumFile
my %versionUID;     # key = md5sum (wie oben), value = uid aus $checkSumFile
my %versionGID;     # key = md5sum (wie oben), value = uid aus $checkSumFile
my %versionMode;    # key = md5sum (wie oben), value = mode aus $checkSumFile
my %versionCTime;   # key = md5sum (wie oben), value = ctime aus $checkSumFile
my %versionMTime;   # key = md5sum (wie oben), value = mtime aus $checkSumFile
my %versionCompr;   # key = md5sum (wie oben), value = c|u aus $checkSumFile
my (@versionMD5s);
my (@dummy);

my $all = @versionDirs + @allDirs;
my $allCount = 0;
my $allActCount = 0;
foreach $entry (@versionDirs)   # jetzt alle zur Datei *gespeicherten*
{                               # unterschiedlichen md5 Summen laden
    if ($verbose)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["reading <$entry>"]);
    }
    else
    {
	if ($allCount++ / $all >= $allActCount / 10)
	{
	    print "$allActCount ";
	    STDOUT->autoflush(1);
	    $allActCount++;
	}
    }

    my $found = 0;
    my $rcsf = readCheckSumFile->new('-checkSumFile' => "$entry/$checkSumFile",
				     '-prLog' => $prLog);
				     
#    my $meta = $rcsf->getMetaValField();
#    my $postfix = ($$meta{'postfix'})->[0];    # postfix (kompr. oder nicht) merken
    my $postfix = $rcsf->getInfoWithPar('postfix');

    my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	$size, $uid, $gid, $mode, $filename);
    while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	    $size, $uid, $gid, $mode, $filename) = $rcsf->nextLine()) > 0)
    {
	$filename .= $postfix if $compr eq 'c';

	if ($fileWithRelPath eq $filename)
	{
	    push @versionMD5s, $md5sum;       # Original md5 Summe merken
	    push @dummy, $entry;
	    $versionMD5sum{$md5sum} = [];
	    $versionSize{$md5sum} = $size;
	    $versionUID{$md5sum} = $uid;
	    $versionGID{$md5sum} = $gid;
	    $versionMode{$md5sum} = $mode;
	    $versionCTime{$md5sum} = $ctime;
	    $versionMTime{$md5sum} = $mtime;
	    $versionCompr{$md5sum} = $compr;
	    $found = 1;
	    last;
	}
    }
    $prLog->print('-kind' => 'E',
                  '-str' => ["cannot find <$fileWithRelPath> in <$entry>"])
        if ($found == 0);
}
(@versionDirs) = (@dummy);

#print "\nOriginal-MD5-Summen:\n";
#print "versionFiles = \n", join("\n", @versionFiles), "\n";
#print "versionMD5s = \n", join("\n", @versionMD5s), "\n";

#
# Alle $checkSumFiles durchgehen und Dateien mit passenden MD5 Summen merken
#
foreach $entry (@allDirs)
{
    if ($verbose)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["checking <$entry>"]);
    }
    else
    {
	if ($allCount++ / $all >= $allActCount / 10)
	{
	    print "$allActCount ";
	    STDOUT->autoflush(1);
	    $allActCount++;
	}
    }

    my $rcsf = readCheckSumFile->new('-checkSumFile' => "$entry/$checkSumFile",
				     '-prLog' => $prLog);

    my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	$size, $uid, $gid, $mode, $filename);
    while ((($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $atime,
	    $size, $uid, $gid, $mode, $filename) = $rcsf->nextLine()) > 0)
    {

	if (exists($versionMD5sum{$md5sum}))
	{
	    push @{$versionMD5sum{$md5sum}}, "$entry/$filename";
#	    print "$md5sum $entry/$filename\n";
	}
    }
#    close(FILE);
}
print "\n" unless $verbose;


# Ausgabe:

# Sortieren der gefundenen Dateien pro md5 Summe
foreach $entry (keys %versionMD5sum)
{
    @{$versionMD5sum{$entry}} = sort @{$versionMD5sum{$entry}};
}

# Aufbauen einer Liste, die so sortiert werden kann, daß die ältesten
# Dateinamen die ersten Versionsnummern bekommen
my @list;
foreach $entry (keys %versionMD5sum)
{
    push @list, {
	'md5' => $entry,
	'list' => $versionMD5sum{$entry},
	'size' => $versionSize{$entry},
	'uid' => $versionUID{$entry},
	'gid' => $versionGID{$entry},
	'mode' => $versionMode{$entry},
	'ctime' => $versionCTime{$entry},
	'mtime' => $versionMTime{$entry},
	'compr' => $versionCompr{$entry}
    };
}
$i = 1;
foreach $entry ( sort { $a->{'list'}[0] cmp $b->{'list'}[0] } @list )
{
    my $pvs = '';
    if ($showSize)
    {
	$pvs = ' ' . (&humanReadable($entry->{'size'}))[0] . ' ' .
	    $entry->{'size'} . ' bytes ';
    if ($entry->{'compr'} eq 'c')
    {
	$pvs .= '(compressed)';
    }
    else
    {
	$pvs .= '(not compressed)';
    }
    }
    print "$i:$pvs (md5=", $entry->{'md5'}, ")\n";
    my @p;
    push @p, 'uid = ' . $entry->{'uid'} if $showUID;
    push @p, 'gid = ' . $entry->{'gid'}  if $showGID;
    push @p, sprintf("mode = 0%o", $entry->{'mode'}) if $showMode;
    print '    ', join(', ', @p), "\n" if (@p);
    @p = ();
    if ($showCTime)
    {
	my $d = dateTools->new('-unixTime' => $entry->{'ctime'});
	push @p, 'ctime = ' . $d->getDateTime();
    }
    if ($showMTime)
    {
	my $d = dateTools->new('-unixTime' => $entry->{'mtime'});
	push @p, 'mtime = ' . $d->getDateTime();
    }
    if ($showATime)
    {
	my $d = dateTools->new('-unixTime' => $entry->{'atime'});
	push @p, 'atime = ' . $d->getDateTime();
    }
    print '    ', join(', ', @p), "\n" if (@p);
    print "\t";
    print join("\n\t", @{$entry->{'list'}}), "\n";
    ++$i;
}

exit 0;
