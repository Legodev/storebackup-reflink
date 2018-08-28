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


$main::STOREBACKUPVERSION = undef;

use strict;
use Net::Ping;
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
	print STDERR "<$file> does not exist, exiting!\n";
        POSIX::_exit 2;
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
        POSIX::_exit 2;
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

require 'splitLine.pl';
require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'forkProc.pl';
require 'dateTools.pl';
require 'version.pl';
require 'tail.pl';
require 'fileDir.pl';

my $tmpdir = '/tmp';              # default value
$tmpdir = $ENV{'TMPDIR'} if defined $ENV{'TMPDIR'};


my $commentMasterBackup =
    "The master backup is the backup you specify with option 'sourceDir' of " .
    "storeBackup.pl (or maybe '-s' on the command line).\nIt is the base " .
    "directory for replication(s); this means after replication to the delta " .
    "cache directory you backups will the stored at this place like without " .
    "any replication.";
my $commentBackupCopy =
    "The backup copy is a copy realized via replication from the master " .
    "backup directory. The deltas (new files) compared to the previous " .
    "backup(s) is replicated to the delta cache directory and then to the " .
    "backup copy directory mentioned here.";
my $commentCacheDir =
    "The delta cache directory is the place to temporarily store your " .
    "changes from backup to backup before they will be copied to your " .
    "backup copy (on an external disk)";

=head1 NAME

storeBackupReplicationWizard.pl - creates configuration files for replication

=head1 SYNOPSIS

    storeBackupReplicationWizard.pl [-m masterBackupDir]
          [-c backupCopyDir] [-d deltaCacheDir] [-S series] [-T tmpdir]

=head1 DESCRIPTION

If you do not specify one of the directories, they will be asked interactive.
This "wizard" can be used for simple configurations only. It allows to create
configuration files for *one* replication of multiple series to eg. *one*
external disk.

If the directories specified do not exist, it will ask whether you want to
create them

=head1 OPTIONS

=over 8

=item B<--masterBackupDir>, B<-m>

    top level directory of the master backup

=item B<--backupCopyDir>, B<-c>

    top level directory of the backup copy (eg. external disk)

=item B<--deltaCacheDir>, B<-d>

    top level directory of the delta cache

=item B<--series>, B<-S>

    series to be replicated
    use this parameter multiple times for multiple series

=item B<--tmpdir>, B<-T>

    directory for temporary files, default is </tmp>

=back

=head1 COPYRIGHT

Copyright (c) 2012-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $binPath = &::absolutePath("$req/../bin");

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-list' =>
		    [Option->new('-name' => 'masterBackupDir',
				 '-cl_option' => '-m',
				 '-cl_alias' => '--masterBackupDir',
				 '-param' => 'yes'),
		     Option->new('-name' => 'backupCopyDir',
				 '-cl_option' => '-c',
				 '-cl_alias' => '--backupCopyDir',
				 '-param' => 'yes'),
		     Option->new('-name' => 'deltaCacheDir',
				 '-cl_option' => '-d',
				 '-cl_alias' => '--deltaCacheDir',
				 '-param' => 'yes'),
		     Option->new('-name' => 'series',
				 '-cl_option' => '-S',
				 '-cl_alias' => '--series',
				 '-param' => 'yes',
				 '-multiple' => 'yes'),
		     Option->new('-name' => 'tmpdir',
				 '-cl_option' => '-T',
				 '-cl_alias' => '--tmpdir',
				 '-default' => $tmpdir)
		    ]
    );

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

my $prLog;
my ($prLogKind) = ['A:BEGIN',
		   'Z:END',
		   'V:VERSION',
		   'I:INFO',
		   'D:DEBUG',
		   'W:WARNING',
		   'E:ERROR'];
$prLog = printLog->new('-kind' => $prLogKind);


# Auswertung der Parameter
my $masterBackupDir = $CheckPar->getOptWithPar('masterBackupDir');
my $masterBackupDirPreset = 1 if $masterBackupDir;
my $backupCopyDir = $CheckPar->getOptWithPar('backupCopyDir');
my $deltaCacheDir = $CheckPar->getOptWithPar('deltaCacheDir');
my $series = $CheckPar->getOptWithPar('series');
(@$series) = sort (@$series) if $series;
$tmpdir = $CheckPar->getOptWithPar('tmpdir');

#
# check if parameters are set
#
$masterBackupDir = &::checkDir($masterBackupDir, 'master backup directory',
			       $commentMasterBackup, $prLog);
$backupCopyDir = &::checkDir($backupCopyDir, 'backup copy directory',
			     $commentBackupCopy, $prLog);
$deltaCacheDir = &::checkDir($deltaCacheDir, 'delta cache directory',
			     $commentCacheDir, $prLog);

$masterBackupDir = &::absolutePath($masterBackupDir);
$backupCopyDir = &::absolutePath($backupCopyDir);
$deltaCacheDir = &::absolutePath($deltaCacheDir);

my $writtenConfFiles = 0;

(@main::cleanup) = ($prLog, undef);
$SIG{INT} = \&cleanup;
$SIG{TERM} = \&cleanup;

#
# check if backup directories are different
#
$prLog->print('-kind' => 'E',
	      '-str' =>
	      ["same path for master backup dir, backup copy dir and " .
	       "delta cache dir were specified.",
	       "Please enter unique paths for each of them"],
	      '-exit' => 1)
    if ($masterBackupDir eq $backupCopyDir and
	$masterBackupDir eq $deltaCacheDir);
$prLog->print('-kind' => 'E',
	      '-str' =>
	      ["same path for master backup dir and backup copy dir " .
	       "were specified.",
	       "Please enter unique paths for each of them"],
	      '-exit' => 1)
    if ($masterBackupDir eq $backupCopyDir);
$prLog->print('-kind' => 'E',
	      '-str' =>
	      ["same path for master backup dir and delta cache dir " .
	       "were specified.",
	       "Please enter unique paths for each of them"],
	      '-exit' => 1)
    if ($masterBackupDir eq $deltaCacheDir);
$prLog->print('-kind' => 'E',
	      '-str' =>
	      ["same path for backup copy dir and delta cache dir " .
	       "were specified.",
	       "Please enter unique paths for each of them"],
	      '-exit' => 1)
    if ($backupCopyDir eq $deltaCacheDir);

#
# check if there's a backup at $masterBackupDir
#
my (@seriesFound) = ();
{
    # try to read series from master backup
    my $s;
    local *DIR;
    opendir(DIR, $masterBackupDir) or
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["cannot opendir <$masterBackupDir>"],
		      '-exit' => 1);
    while ($s = readdir DIR)
    {
	my $entry = "$masterBackupDir/$s";
	next if ($s eq '.' or $s eq '..');
	next if -l $entry and not -d $entry;  # only directories
	next unless -d $entry;

	push @seriesFound, $s;
    }
    closedir(DIR);
    (@seriesFound) = sort (@seriesFound);

    # check for existing backups
    my (@p) = ("$masterBackupDir/*/*/.storeBackupLinks");
    my (@b) = <@p>;

    unless (@b)
    {
	$prLog->print('-kind' => 'W',
		      '-str' =>
		      ["cannot find any existing backup at " .
		       "master backup directory <$masterBackupDir>"]);
	unless ($masterBackupDirPreset)
	{
	    my $answer = undef;
	    do
	    {
		print "\nis this ok?\n",
		"yes / no -> ";
		$answer = <STDIN>;
		chomp $answer;
	    } while ($answer ne 'yes' and $answer ne 'no');
	    exit 1 if $answer eq 'no';
	}
    }
    else   # there is something in the master backup
    {
	unless ($series)
	{

	    my $answer = undef;
	    do
	    {
		print "\nfound series <", join('> <', @seriesFound), ">\n",
		(@seriesFound == 1 ? "replicate it?\n" :"replicate them all?\n"),
		"yes / no -> ";
		$answer = <STDIN>;
		chomp $answer;
	    } while ($answer ne 'yes' and $answer ne 'no');

	    if ($answer eq 'yes')
	    {
		(@$series) = @seriesFound;
	    }
	    else
	    {
		print "\ntype series names separated by blanks\n",
		"(use quotes if there is a blank in a name)\n",
		"-> ";
		my $s = <STDIN>;
		chomp $s;
		$series = &ConfigFile::splitQuotedLine($s, '', 1);
		(@$series) = sort (@$series);
	    }
	}
    }
}

$prLog->print('-kind' => 'I',
	      '-str' => [scalar @$series . " series chosen:",
			 "\t<" . join('> <', @$series) . ">"])
    if ($series);

#
# check if series specified exist
#
{
    my (%seriesFound);
    foreach my $s (@seriesFound)
    {
	$seriesFound{$s} = 1;
    }
    my (@sFound, @sNotFound);
    foreach my $s (@$series)
    {
	if (exists $seriesFound{$s})
	{
	    push @sFound, $s;
	}
	else
	{
	    push @sNotFound, $s;
	}
    }
    if (@$series == 0)
    {
	print "\ntype series names you want to replicate separated by blanks\n",
	"(use quotes if there is a blank in a name)\n",
	"-> ";
	my $s = <STDIN>;
	chomp $s;
	$series = &ConfigFile::splitQuotedLine($s, '', 1);
	(@$series) = sort (@$series);
    }
    elsif (@sNotFound)
    {
	my $answer = undef;
	do
	{
	    print
	    "\nthe following selected series were found at <$masterBackupDir>:\n",
	    "\t<", join('> <', sort @sFound), ">\n",
	    "but the following selected series were *not* found:\n",
	    "\t<", join('> <', sort @sNotFound), ">\n",
	    "continue with the selection, stop, change:\n",
	    "continue / stop / change -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'continue' and $answer ne 'stop' and
		 $answer ne 'change');
	if ($answer eq 'stop')
	{
	    exit 1;
	}
	elsif ($answer eq 'change')
	{
	    my $answer = undef;
	    do
	    {
		print "\nfound series <", join('> <', @seriesFound), ">\n",
		"replicate them all?\n",
		"yes / no -> ";
		$answer = <STDIN>;
		chomp $answer;
	    } while ($answer ne 'yes' and $answer ne 'no');

	    if ($answer eq 'yes')
	    {
		(@$series) = @seriesFound;
	    }
	    else
	    {
		print
		"\ntype series names you want to replicate separated by blanks\n",
		"(use quotes if there is a blank in a name)\n",
		"-> ";
		my $s = <STDIN>;
		chomp $s;
		$series = &ConfigFile::splitQuotedLine($s, '', 1);
		(@$series) = sort (@$series);
	    }
	}
    }
}

#
# generate configuration files
#
my $tmpDir = &::uniqFileName("$tmpdir/stbuRW-");
mkdir $tmpDir, 0700 or
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot create temporary directory <$tmpDir>"],
		  '-exit' => 1);

(@main::cleanup) = ($prLog, $tmpDir);

{
    my $f = forkProc->new('-exec' => "$binPath/storeBackupUpdateBackup.pl",
			  '-param' => ['--genBackupBaseTreeConf', $tmpDir],
			  '-outRandom' => "$tmpDir/stbuUpdate-",
			  '-prLog' => $prLog);
    $f->wait();
    my $out = $f->getSTDOUT();
    $prLog->print('-kind' => 'W',
		  '-str' =>
		  ["STDOUT of <$binPath/storeBackupUpdateBackup.pl " .
		   "--genBackupBaseTreeConf>:", @$out])
	if (@$out > 0);
    $out = $f->getSTDERR();
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["STDERR of <$binPath/storeBackupUpdateBackup.pl " .
		   "--genBackupBaseTreeConf>:", @$out],
		  '-exit' => 1)
	if (@$out > 0);

    $f = forkProc->new('-exec' => "$binPath/storeBackupUpdateBackup.pl",
		       '-param' => ['--genDeltaCacheConf', $tmpDir],
		       '-outRandom' => "$tmpDir/stbuUpdate-",
		       '-prLog' => $prLog);
    $f->wait();
    $out = $f->getSTDOUT();
    $prLog->print('-kind' => 'W',
		  '-str' =>
		  ["STDOUT of <$binPath/storeBackupUpdateBackup.pl " .
		   "--genDeltaCacheConf>:", @$out])
	if (@$out > 0);
    $out = $f->getSTDERR();
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["STDERR of <$binPath/storeBackupUpdateBackup.pl " .
		   "--genDeltaCacheConf>:", @$out],
		  '-exit' => 1)
	if (@$out > 0);
}

#
# copy / create configuration files from $tmpDir to their location
#
# generate master backup configuration file
{
    my $fIn = "$tmpDir/storeBackupBaseTree.conf";
    my $fOut = "$masterBackupDir/storeBackupBaseTree.conf";
    my $writeConfigFile = 1;
    if (-e $fOut)
    {
	my $answer = undef;
	do
	{
	    print "\nConfiguration file for master backup directory\n",
	    "<$masterBackupDir> already exists. How to proceed:\n",
	    "overwrite / continue / stop -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'overwrite' and $answer ne 'stop' and
		 $answer ne 'continue');
	if ($answer eq 'stop')
	{
	    exit 1;
	}
	elsif ($answer eq 'continue')
	{
	    $writeConfigFile = 0;
	}
    }

    if ($writeConfigFile)
    {
	my $l;
	local *IN, *OUT;
	open(IN, '<', $fIn) or
	    $prLog->print('-kind' => 'E',
		      '-str' => ["cannot open temporary file <$fIn>"],
			  '-exit' => 1);
	open(OUT, '>', $fOut) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open file <$fOut>"],
			  '-exit' => 1);
	while ($l = <IN>)
	{
	    chomp $l;
	    if ($l =~ /\A;(backupTreeName)=\s*\Z/)
	    {
		print OUT "$1='Master Backup'\n";
	    }
	    elsif ($l =~ /\A;(backupType)=\s*\Z/)
	    {
		print OUT "$1=master\n";
	    }
	    elsif ($l =~ /\A;(seriesToDistribute)=\s*\Z/)
	    {
		print OUT "$1='", join('\' \'', @$series), "'\n";
	    }
	    elsif ($l =~ /\A;(deltaCache)=\s*\Z/)
	    {
		print OUT "$1=$deltaCacheDir\n";
	    }
	    else
	    {
		print OUT "$l\n";
	    }
	}
	close(IN);
	close(OUT);
	$writtenConfFiles |= 1;
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["wrote master backup configuration file " .
		       "<$fOut>"]);
    }
}
# generate backup copy configuration file
{
    my $fIn = "$tmpDir/storeBackupBaseTree.conf";
    my $fOut = "$backupCopyDir/storeBackupBaseTree.conf";
    my $writeConfigFile = 1;
    if (-e $fOut)
    {
	my $answer = undef;
	do
	{
	    print "\nConfiguration file for backup copy directory\n",
	    "<$backupCopyDir> already exists. How to proceed:\n",
	    "overwrite / continue / stop -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'overwrite' and $answer ne 'stop' and
		 $answer ne 'continue');
	if ($answer eq 'stop')
	{
	    exit 1;
	}
	elsif ($answer eq 'continue')
	{
	    $writeConfigFile = 0;
	}
    }

    if ($writeConfigFile)
    {
	my $l;
	local *IN, *OUT;
	open(IN, '<', $fIn) or
	    $prLog->print('-kind' => 'E',
		      '-str' => ["cannot open temporary file <$fIn>"],
			  '-exit' => 1);
	open(OUT, '>', $fOut) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open file <$fOut>"],
			  '-exit' => 1);
	while ($l = <IN>)
	{
	    chomp $l;
	    if ($l =~ /\A;(backupTreeName)=\s*\Z/)
	    {
		print OUT "$1='Backup Copy'\n";
	    }
	    elsif ($l =~ /\A;(backupType)=\s*\Z/)
	    {
		print OUT "$1=copy\n";
	    }
	    elsif ($l =~ /\A;(seriesToDistribute)=\s*\Z/)
	    {
		print OUT "$1='", join('\' \'', @$series), "'\n";
	    }
	    elsif ($l =~ /\A;(deltaCache)=\s*\Z/)
	    {
		print OUT "$1=$deltaCacheDir\n";
	    }
	    else
	    {
		print OUT "$l\n";
	    }
	}
	close(IN);
	close(OUT);
	$writtenConfFiles |= 2;
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["wrote backup copy configuration file " .
		       "<$fOut>"]);
    }
}
# generate backup copy configuration file
{
    my $fIn = "$tmpDir/deltaCache.conf";
    my $fOut = "$deltaCacheDir/deltaCache.conf";
    my $writeConfigFile = 1;
    if (-e $fOut)
    {
	my $answer = undef;
	do
	{
	    print "\nConfiguration file for delta cache directory\n",
	    "<$deltaCacheDir> already exists. How to proceed:\n",
	    "overwrite / continue / stop -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'overwrite' and $answer ne 'stop' and
		 $answer ne 'continue');
	if ($answer eq 'stop')
	{
	    exit 1;
	}
	elsif ($answer eq 'continue')
	{
	    $writeConfigFile = 0;
	}
    }

    if ($writeConfigFile)
    {
	my $l;
	local *IN, *OUT;
	open(IN, '<', $fIn) or
	    $prLog->print('-kind' => 'E',
		      '-str' => ["cannot open temporary file <$fIn>"],
			  '-exit' => 1);
	open(OUT, '>', $fOut) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open file <$fOut>"],
			  '-exit' => 1);
	while ($l = <IN>)
	{
	    chomp $l;
	    if ($l =~ /\A;(backupCopy0)=\s*\Z/)
	    {
		print OUT "$1='Backup Copy'" .
		    " '", join('\' \'', @$series), "'\n";
	    }
	    else
	    {
		print OUT "$l\n";
	    }
	}
	close(IN);
	close(OUT);
	$writtenConfFiles |= 4;
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["wrote delta cache configuration file " .
		       "<$fOut>"]);
    }
}

$prLog->print('-kind' => 'W',
	      '-str' => ["not all configuration files were written,",
			 "so they might be inconsistent - please check"])
    unless $writtenConfFiles == (1|2|4);

# delete temporary files / directory
unlink "$tmpDir/storeBackupBaseTree.conf", "$tmpDir/deltaCache.conf";
rmdir $tmpDir;

exit 0;



##################################################
sub checkDir
{
    my ($dir, $name, $comment, $prLog) = @_;

    my $c = "\n";
    foreach my $l (&::splitLine($comment, 79, '\s+', "\n"))
    {
	$c .= "$l\n";
    }

    unless ($dir)
    {
	print $c;
	$c = undef;
	my $answer = '';
	do
	{
	    print "\n$name is not yet defined, please enter path\n",
	    "-> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer =~ /\A\s*\Z/);

	$dir = $answer;
    }

    unless (-e $dir)
    {
	print $c if $c;
	my $answer = undef;
	do
	{
	    print "\n$name does not exist at <$dir>\n",
	    "should I create it?\n",
	    "yes / no -> ";
	    $answer = <STDIN>;
	    chomp $answer;
	} while ($answer ne 'yes' and $answer ne 'no');

	exit 1 if $answer eq 'no';

	&::makeDirPath($dir, $prLog) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot create $name <$dir>"],
			  '-exit' => 1);
	$prLog->print('-kind' => 'I',
		      '-str' => ["created $name <$dir>"]);
    }

    return $dir;
}


##################################################
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    my ($prLog, $tmpDir) = (@main::cleanup);

    print "\n";
    if ($signame)
    {
        $prLog->print('-kind' => 'E',
                      '-str' => ["caught signal $signame, terminating"]);
    }

    # delete temporary files / directory
    if ($tmpDir)
    {
	unlink "$tmpDir/storeBackupBaseTree.conf", "$tmpDir/deltaCache.conf";
	rmdir $tmpDir;
    }

    exit $exit;
}
