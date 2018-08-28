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


use IO::Handle;
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

require 'version.pl';
require 'fileDir.pl';

my $md5CheckSums = '.md5CheckSums';

=head1 NAME

storeBackupConvertBackup.pl - converts old backups created with storeBackup.pl to the newest version,

=head1 SYNOPSIS

storeBackupConvertBackup.pl storeBackup-dir

=head1 DESCRIPTION

This program converts old backups created with storeBackup.pl to the newest version,
currently version 1.3.
you can see the version by typing:

head -1 < ...<storeBackupDir>/date_time/.md5CheckSums.info

or if that file does not exist:

bzip2 -d < ...<storeBackupDir>/date_time/.md5CheckSums.bz2 | head -1

(if you do not see '###version=...', it is version 1.0

=head1 COPYRIGHT

Copyright (c) 2002-2014 by Heinz-Josef Claes (see README)
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

die $Help if (@ARGV != 1);

my $dir = shift @ARGV;
die "directory <$dir> does not exist" unless (-d $dir);

opendir(DIR, $dir) or
    die "cannot open <$dir>";
my ($entry, @entries);
while ($entry = readdir DIR)
{
    my $e = "$dir/$entry";
    next if (-l $e and not -d $e);
    push @entries, $entry;
}
closedir(DIR);

my $flag = 0;
my $i = 1;
foreach $entry (sort @entries)
{
    next unless $entry =~
	/\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;

    $flag = 1;   # irgendein directory gefunden

    my $e = "$dir/$entry";
    my $compress = 0;

againForNextVersion:
    if (-f "$e/$md5CheckSums.info") # ab Version 1.2
    {
	if (-f "$e/$md5CheckSums.bz2")  # komprimierte Version liegt vor, nehmen
	{
	    $compress = 1;
	}
	elsif (-f "$e/$md5CheckSums")
	{
	    $compress = 0;
	}
	else
	{
	    print "cannot open <$e/$md5CheckSums\[.bz2\]>\n";
	    next;
	}

	open(INFO, "$e/$md5CheckSums.info") or
	    die "cannot open <$e/$md5CheckSums.info";
	my $v;
	my $l = <INFO>;
	chop $l;
	if ($l =~ /^version=(\S+)/)
	{
	    $v = $1;
	}
	else
	{
	    print "cannot find version information in $e/$md5CheckSums.info\n";
	    next;
	}
	if ($v eq '1.3')
	{
	    print "$entry: version <$v> => ok.\n";
	}
	elsif ($v eq '1.2')
	{
	    print "$entry: version <$v> converting to 1.3 ...";
	    STDOUT->autoflush(1);
	    my ($uid, $gid, $mode);
	    if ($compress == 1)
	    {
		($uid, $gid, $mode) = (stat("$e/$md5CheckSums.bz2"))[4, 5, 2];
		unlink "$e/$md5CheckSums.new.bz2", "$e/$md5CheckSums.info";
		open(FILE, "bzip2 -d < \'$e/$md5CheckSums.bz2\' |") or
		    die "cannot open $e/$md5CheckSums.bz2";
		open(NEW, "| bzip2 > \'$e/$md5CheckSums.new.bz2\'") or
		    die "cannot bzip2 > $e/$md5CheckSums.new.bz2";
	    }
	    else
	    {
		($uid, $gid, $mode) = (stat("$e/$md5CheckSums"))[4, 5, 2];
		unlink "$e/$md5CheckSums.new", "$e/$md5CheckSums.info";
		open(FILE, "< $e/$md5CheckSums") or
		    die "cannot open $e/$md5CheckSums";
		open(NEW, "> $e/$md5CheckSums.new") or
		    die "cannot write $e/$md5CheckSums.new";
	    }
	    $mode &= 07777;
	    $l = <FILE>;     # erste Zeile überlesen
	    print NEW "# contents/md5 compr dev-inode inodeBackup ctime mtime atime size uid gid mode filename\n";

	    open(INFO_NEW, "> $e/$md5CheckSums.info.new") or
		die "cannot write $e/$md5CheckSums.info.new";

	    while ($l = <FILE>)
	    {
		chop $l;
		my ($md5sum, $compr, $devInode, $inodeBackup, $ctime, $mtime, $size,
		    $uid, $gid, $mode, $filename);
		my $d = '[\d-]';      # \d und Minuszeichen
		my $n = ($md5sum, $compr, $devInode, $inodeBackup, $ctime,
			 $mtime, $size, $uid, $gid, $mode, $filename) =
			     $l =~ /^(\w+)\s+(\w+)\s+(\S+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+(.*)/o;
		if ($n != 11)
		{
		    print "cannot read line: <$l>\n";
		}

		my $atime = $mtime;
		print NEW "$md5sum $compr $devInode $inodeBackup $ctime " .
		    "$mtime $atime $size $uid $gid $mode $filename\n";
	    }
	    close(FILE);
	    close(NEW);
	    print INFO_NEW "version=1.3\n";
	    my (@l) = <INFO>;
	    print INFO_NEW "@l";
	    close(INFO_NEW);
	    print "\n";
	    if ($compress == 1)
	    {
		unlink "$e/$md5CheckSums.bz2";
		rename "$e/$md5CheckSums.new.bz2", "$e/$md5CheckSums.bz2";
		chown $uid, $gid, "$e/$md5CheckSums.bz2";
		chmod $mode, "$e/$md5CheckSums.bz2";
	    }
	    else
	    {
		unlink "$e/$md5CheckSums";
		rename "$e/$md5CheckSums.new", "$e/$md5CheckSums";
		chown $uid, $gid, "$e/$md5CheckSums";
		chmod $mode, "$e/$md5CheckSums";
	    }
	    mkdir "$e/.storeBackupLinks", 0777;
	    unlink "$e/$md5CheckSums.info";
	    rename "$e/$md5CheckSums.info.new", "$e/$md5CheckSums.info";
	}
	else
	{
	    print "$entry: unsupported version <$v>\n";
	}
	close(INFO);
    }
    else                            # Version 1.0 und 1.1
    {
	if (-f "$e/$md5CheckSums.bz2")  # komprimierte Version liegt vor, nehmen
	{
	    open(FILE, "bzip2 -d < \'$e/$md5CheckSums.bz2\' |");
	    $compress = 1;
	}
	elsif (-f $e/$md5CheckSums)
	{
	    open(FILE, "< $e/$md5CheckSums");
	}
	else
	{
	    print "cannot open <$e/$md5CheckSums\[.bz2\]>\n";
	    next;
	}
	my $v;
	my $l = <FILE>;
	chop $l;
	if ($l =~ /^###version=(.*)/)
	{
	    $v = $1;
	}
	else
	{
	    $v = '1.0';
	}

	if ($v eq '1.0')
	{
	    print "$entry: version <$v> converting to 1.1 ...";
	    STDOUT->autoflush(1);
	    if ($compress == 1)
	    {
		unlink "$e/$md5CheckSums.new.bz2";
		open(NEW, "| bzip2 > \'$e/$md5CheckSums.new.bz2\'") or
		    die "cannot bzip2 > $e/$md5CheckSums.new.bz2";
	    }
	    else
	    {
		unlink "$e/$md5CheckSums.new";
		open(NEW, "> $e/$md5CheckSums.new") or
		    die "cannot write $e/$md5CheckSums.new";
	    }
	    print NEW "###version=1.1\n";
	    print NEW "###exceptDirsSep=,\n";
	    print NEW "###exceptDirs=\n";

	    my $i = 0;    # Zähler, der inodes simuliert
	    while ($l = <FILE>)
	    {
		if ($l =~ /^###/)
		{
		    print NEW $l;
		    next;
		}

		$i++;
		chop $l;
		my ($md5sum, $compr, $ctime, $mtime, $size, $uid, $gid,
		    $mode, $filename);
		my $d = '[\d-]';      # \d und Minuszeichen
		my $n = ($md5sum, $compr, $ctime, $mtime, $size, $uid,
			 $gid, $mode, $filename) =
		$l =~ /^(\w+)\s+(\w+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+(.*)/o;
		print NEW
		    "$md5sum $compr 1-$i $ctime $mtime $size $uid $gid $mode $filename\n";
	    }
	    close(NEW);
	    if ($compress == 1)
	    {
		unlink "$e/$md5CheckSums.bz2";
		rename "$e/$md5CheckSums.new.bz2", "$e/$md5CheckSums.bz2";
		chmod 0600, "$e/$md5CheckSums.bz2";
	    }
	    else
	    {
		unlink "$e/$md5CheckSums";
		rename "$e/$md5CheckSums.new", "$e/$md5CheckSums";
		chmod 0600, "$e/$md5CheckSums";
	    }
	    print " ok\n";

	    goto againForNextVersion;
	}
	elsif ($v eq '1.1')
	{
	    print "$entry: version <$v> converting to 1.2 ...";
	    STDOUT->autoflush(1);
	    if ($compress == 1)
	    {
		unlink "$e/$md5CheckSums.new.bz2", "$e/$md5CheckSums.info";
		open(NEW, "| bzip2 > \'$e/$md5CheckSums.new.bz2\'") or
		    die "cannot bzip2 > $e/$md5CheckSums.new.bz2";
	    }
	    else
	    {
		unlink "$e/$md5CheckSums.new", "$e/$md5CheckSums.info";
		open(NEW, "> $e/$md5CheckSums.new") or
		    die "cannot write $e/$md5CheckSums.new";
	    }
	    open(INFO, "> $e/$md5CheckSums.info") or
		die "cannot write $e/$md5CheckSums.info";

	    print INFO "version=1.2\n";

	    my $postfix;
	    while ($l = <FILE>)
	    {
		if ($l =~ /^### /)   # Spaltenverzeichnis
		{
		    print NEW "# contents/md5 compr dev-inode inodeBackup " .
			"ctime mtime size uid gid mode filename\n";
		    next;
		}
		elsif ($l =~ /^###(.*?)=(.*)/)
		{
		    print INFO "$1=$2\n";
		    $postfix = $2 if ($1 eq 'postfix');
		    next;
		}

		chop $l;
		my ($md5sum, $compr, $devInode, $ctime, $mtime, $size, $uid, $gid,
		    $mode, $filename);
		my $d = '[\d-]';      # \d und Minuszeichen
		my $n = ($md5sum, $compr, $devInode, $ctime, $mtime, $size, $uid,
			 $gid, $mode, $filename) =
		$l =~ /^(\w+)\s+(\w+)\s+(\S+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+($d+)\s+(.*)/o;
		# Inode im Backup ermitteln
		my $inodeBackup;
		my $f = "$e/$filename";
		$f =~ s/\\0A/\n/og;    # '\n' wiederherstellen
		$f =~ s/\\5C/\\/og;    # '\\' wiederherstellen

		$f .= $postfix if ($compr eq 'c');
		if ($md5sum eq 'symlink')
		{
		    $inodeBackup = (lstat($f))[1];
		}
		else
		{
		    $inodeBackup = (stat($f))[1];
		}

		print NEW
		    "$md5sum $compr $devInode $inodeBackup $ctime $mtime " .
		       "$size $uid $gid $mode $filename\n";
	    }
	    close(NEW);
	    close(INFO);
	    chmod 0600, "$e$md5CheckSums.info";
	    if ($compress == 1)
	    {
		unlink "$e/$md5CheckSums.bz2";
		rename "$e/$md5CheckSums.new.bz2", "$e/$md5CheckSums.bz2";
		chmod 0600, "$e/$md5CheckSums.bz2";
	    }
	    else
	    {
		unlink "$e/$md5CheckSums";
		rename "$e/$md5CheckSums.new", "$e/$md5CheckSums";
		chmod 0600, "$e/$md5CheckSums";
	    }
	    print " ok\n";
	    close(FILE);
	}
	else
	{
	    print "$entry: unsupported version <$v>\n";
	}
    }
}


print "ERROR: no backup directories found\n"
    unless ($flag);

