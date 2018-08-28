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


=head1 NAME

storeBackupSetupIsolatedMode.pl - copy last storeBackup meta data
of a series to eg. a stick

=head1 DESCRIPTION

copies the meta data of a backup to another filesystem (eg. a memory
stick); optinoally generates a customised version of the storeBackup
configuration file
This can be used to generate incremental backup eg. during travel.
These can be integrated into the full backup via
storeBackupMergeIsolatedBackup.pl and storeBackupUpdateBackup.pl


=head1 SYNOPSIS

based on configuration file:

    storeBackupSetupIsolatedMode.pl -f configFile -t targetDir
    				[-S series] [-g newConfigFile]
				[-e explicitBackup] [-v] [-F]


no configuration file:

    storeBackupSetupIsolatedMode.pl -b backupDir -t targetDir
    				[-S series] [-e explicitBackup] [-v] [-F]

=head1 OPTIONS

=over 8

=item B<--configFile>, B<-f>

    (original, non-isolated mode) configuration file to copy for
    isolated mode also used to get value for backupDir and series.
    You can also use an already generated configuration file to
    repeat the set up with the same configuration as in the past.

=item B<--targetDir>, B<-t>

    directory where to write the new configuration file for
    isolated mode. Also, the series directory is created in
    targetDir and the meta data from the last backup in
    backupDir is copied to targetDir/series

=item B<--generate>, B<-g>

    (path and) file name of the configuration file to generate.
    Default is isolate-<name specified at --configFile> in
    the same directory as configFile

=item B<--backupDir>, B<-b>

    backup directory from which meta data have to be
    copied eg. on an usb stick.
    If more than one series exists in this backup,
    you have to specify option series also

=item B<--series>, B<-S>

    series of which meta data have to be copied to targetDir.
    Has to be specified if more than one series exist
    in backupDir

=item B<--explicitBackup>, B<-e>

    explicit Backup which has to be copied
    default is the last backup of the specified series

=item B<--verbose>, B<-v>

    generate verbose messages

=item B<--force>, B<-F>

    force usage of last backup (with lateLinks), even it if has
    not been completed with storeBackupUpdateBackup.pl

=back

=head1 COPYRIGHT

Copyright (c) 2012-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

&printVersion(\@ARGV, '-V', '--version');

my $CheckPar =
    CheckParam->new('-allowLists' => 'no',
		    '-list' => [Option->new('-name' => 'backupDir',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupDir',
					    '-param' => 'yes',
					    '-only_if' => 'not [configFile]'),
				Option->new('-name' => 'series',
					    '-cl_option' => '-S',
					    '-cl_alias' => '--series',
					    '-param' => 'yes',
					    '-only_if' => '[backupDir]'),
				Option->new('-name' => 'explicitBackup',
					    '-cl_option' => '-e',
					    '-cl_alias' => '--explicitBackup',
					    '-param' => 'yes'),
				Option->new('-name' => 'configFile',
					    '-cl_option' => '-f',
					    '-cl_alias' => '--configFile',
					    '-param' => 'yes',
					    '-only_if' => 'not [backupDir]'),
				Option->new('-name' => 'targetDir',
					    '-cl_option' => '-t',
					    '-cl_alias' => '--targetDir',
					    '-param' => 'yes',
#					    '-must_be' => 'yes'),
					    ),
				Option->new('-name' => 'generate',
					    '-cl_option' => '-g',
					    '-cl_alias' => '--generate',
					    '-param' => 'yes',
					    '-only_if' => '[configFile]'),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose'),
				Option->new('-name' => 'force',
					    '-cl_option' => '-F',
					    '-cl_alias' => '--force')
				]);

$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

my $backupDir = $CheckPar->getOptWithPar('backupDir');
my $series = $CheckPar->getOptWithPar('series');  # must be specified if
                                                  # more than 1 series exist
my $explicitBackup = $CheckPar->getOptWithPar('explicitBackup');
my $configFile = $CheckPar->getOptWithPar('configFile');
my $generateConfigFile = $CheckPar->getOptWithPar('generate');
my $targetDir = $CheckPar->getOptWithPar('targetDir');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $force = $CheckPar->getOptWithoutPar('force');


my $prLog;
my ($prLogKind) = ['A:BEGIN',
		   'Z:END',
		   'I:INFO',
		   'W:WARNING',
		   'E:ERROR'];
$prLog = printLog->new('-kind' => $prLogKind);


$prLog->print('-kind' => 'E',
	      '-str' => ["please define <configFile> or <backupDir>"],
	      '-exit' => 1)
    unless ($configFile or $backupDir);


my $otherBackupSeries = undef;
my $lateLinks = undef;
my $lateCompress = undef;
my $useOldConfig = 0;
if ($configFile)    # get information from config file
{
    my $confOld =
	CheckParam->new('-configFile' => '-f',
			'-list' => [
			    Option->new('-name' => 'oldConfigFile',
					'-cl_option' => '-f',
					'-param' => 'yes'),
			    Option->new('-name' => 'backupDir',
					'-cf_key' => 'backupDir',
					'-param' => 'yes'),
			    Option->new('-name' => 'series',
					'-cf_key' => 'series',
					'-default' => 'default'),
			    Option->new('-name' => 'lateLinks',
					'-cf_key' => 'lateLinks',
					'-cf_noOptSet' => ['yes', 'no']),
			    Option->new('-name' => 'lateCompress',
					'-only_if' => '[lateLinks]',
					'-cf_key' => 'lateCompress',
					'-cf_noOptSet' => ['yes', 'no']),
			    Option->new('-name' => 'mergeBackupDir',
					'-cf_key' => 'mergeBackupDir',
					'-param' => 'yes'),
			]);
    $confOld->check('-argv' => ['-f' => $configFile],
		    '-help' => "cannot read file <$configFile>\n",
		    '-ignoreAdditionalKeys' => 1);

    my $mergeBackupDir = $confOld->getOptWithPar('mergeBackupDir');
    if ($mergeBackupDir)
    {
	$backupDir = $confOld->getOptWithPar('mergeBackupDir');
	$targetDir = $confOld->getOptWithPar('backupDir');
	$useOldConfig = 1;
    }
    else
    {
	$backupDir = $confOld->getOptWithPar('backupDir');
    }
    $series = $confOld->getOptWithPar('series');
    $lateLinks = $confOld->getOptWithoutPar('lateLinks');
    $lateCompress = $confOld->getOptWithoutPar('lateCompress');
}
else     # do not read configuration file
{
    unless ($series)    # check name of series
    {
	local *DIR;
	opendir(DIR, $backupDir) or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot opendir <$backupDir>, exiting"],
			  '-add' => [__FILE__, __LINE__],
			  '-exit' => 1);
	my ($entry, @entries);
	while ($entry = readdir DIR)
	{
	    next if ($entry eq '.' or $entry eq '..');
	    my $e = "$backupDir/$entry";
	    next if (-l $e and not -d $e);   # only directories
	    next unless -d $e;
	    push @entries, $entry;
	}
	closedir(DIR);

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["no series found in <$backupDir>, exiting"],
		      '-exit' => 1)
	    if @entries == 0;
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["found more than one backup series, please specify ",
		      "series with option --series; found:", sort @entries],
		      '-exit' => 1)
	    if @entries > 1;

	$series = $entries[0];
    }
}

$prLog->print('-kind' => 'E',
	      '-str' => ["backup directory <$backupDir> does not exist"],
	      '-exit' => 1)
    unless (-d $backupDir);
$prLog->print('-kind' => 'E',
	      '-str' => ["please specify targetDir"],
	      '-exit' => 1)
    unless ($targetDir);
$prLog->print('-kind' => 'E',
	      '-str' => ["target directory <$targetDir> does not exist"],
	      '-exit' => 1)
    unless (-d $targetDir);
$prLog->print('-kind' => 'E',
	      '-str' =>
	      ["series directory <$series> does not exist inside <$backupDir>"],
	      '-exit' => 1)
    unless (-d "$backupDir/$series");

$prLog->print('-kind' => 'I',
	      '-str' => ["found series <$series> in backupDir <$backupDir>"])
    if $verbose;

my $targetSeriesDir = "$targetDir/$series";

#
# detect last backup
#
my $lastBackupDir = undef;
if ($explicitBackup)
{
    $lastBackupDir = "$backupDir/$series/$explicitBackup";
    $prLog->print('-kind' => 'E',
		  '-str' => ["explicit backup <$lastBackupDir> does not exist"],
		  '-exit' => 1)
	unless -d $lastBackupDir;
}
else
{
    local *DIR;
    opendir(DIR, "$backupDir/$series") or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot opendir <$backupDir/$series>, exiting"],
		      '-add' => [__FILE__, __LINE__],
		      '-exit' => 1);
    my ($entry, @entries);
    while ($entry = readdir DIR)
    {
	next if (-l $entry and not -d $entry);   # only directories
	push @entries, $entry
	    if $entry =~
	    /\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\Z/o;
    }
    closedir(DIR);

    @entries = sort @entries;    # newest backup first
    my $e;
    foreach $e (@entries)
    {
#	if (-e "$backupDir/$series/$e/.md5CheckSums.notfinished")
	unless (&::checkIfBackupWasFinished('-backupDir' => "$backupDir/$series/$e",
					    '-prLog' => $prLog,
			    '-count' => 50))
	{
	    $prLog->print('-kind' => 'W',
			  '-str' => ["<$backupDir/$series/$e> not finished"]);
	}
	else
	{
	    $lastBackupDir = "$backupDir/$series/$e";
	}
    }
    $prLog->print('-kind' => 'E',
		  '-str' =>
		  ["no series found in <$backupDir>, exiting"],
		  '-exit' => 1)
	unless $lastBackupDir;

    $prLog->print('-kind' => 'E',
		  '-str' =>
       ["last backupDir <$backupDir> needs",
	"to run storeBackupUpdateBackup.pl, ",
	"please do so and repeat running this program",
	"or use option --explicitBackup or option --force"],
		  '-exit' => 1)
	if -e "$lastBackupDir/.storeBackupLinks/linkFile.bz2"
	and not $force;

    $prLog->print('-kind' => 'I',
		  '-str' =>
		  ["last directory with backup is <$lastBackupDir>"])
	if $verbose;
}

if ($configFile and not $useOldConfig)  # copy configuration file
{
    unless ($generateConfigFile)
    {
	my ($b_dir, $b_file) = &::splitFileDir($configFile);
	$generateConfigFile = "$b_dir/isolate-$b_file";
    }

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

    # read config file and copy
    local *FILE;
    open(FILE, $configFile) or
	$prLog->print('-kind' => 'E',
		      '-str' => "cannot open <$configFile>",
		      '-exit' => 1);
    my (@configFile) = <FILE>;
    chomp @configFile;
    close(FILE);

    open(FILE, '>', $generateConfigFile) or
	$prLog->print('-kind' => 'E',
		      '-str' => "cannot open <$generateConfigFile>",
		      '-exit' => 1);

    my (%checkKeys) = ('backupDir' => 1,
		       'lateLinks' => 1);
    my (%keys, $l);
    my (@cf) = (@configFile);       # working copy of @configFile
    my $actKey = undef;
    my $i = 0;
    my $printNextLine = 1;
    my (@comments) = ();
    foreach $l (@cf)
    {
	$i++;

	if ($l =~ /\A[#]/ or $l =~ /\A\s*\Z/)  # comment or empty
	{
	    push @comments, $l;
	    $actKey = undef;
	    next;
	}
	if ($l =~ /\A\s+/)
	{
	    die "continue line with no key at line $i:\n<",
	    $configFile[$i-1], ">\n" unless $actKey;
	    $keys{$actKey}{'line'} .= ' ' . $l;

	    print FILE "$l\n"
		if $printNextLine;
	}
	else
	{
	    my ($semicolon, $key, $line);
	    if (($semicolon, $key, $line) = $l =~ /\A(;?)(.+?)\s*=\s*(.*)\Z/)
	    {
		$actKey = $key;
		$keys{$actKey}{'line'} = $line;
		$keys{$actKey}{'lineno'} = $i;

		if ($key eq 'backupDir')
		{
		    $printNextLine = 1;
		    print FILE join("\n", @comments),
		    "\n$key=\"$targetDir\"\n\n";
		    # mergeBackupDir
		    print FILE
			"# backupDir for merging the backups generated in ",
			"isolated mode\n# later in main backup\n",
			"mergeBackupDir=$line\n";
		    $prLog->print('-kind' => 'I',
				  '-str' =>
		      ["$generateConfigFile: changed <backupDir> " .
		       "to '$targetDir'",
		      "$generateConfigFile: created <mergeBackupDir> " .
		       "as '$line'"]);
		    delete $checkKeys{$key};
		}
		elsif ($key eq 'mergeBackupDir')
		{
		    $printNextLine = 0;
		    print FILE join("\n", @comments), "\n;$key=$line\n";
		    $prLog->print('-kind' => 'I',
				  '-str' =>
         		  ["$generateConfigFile: disabled existing key $key=$line"])
			if ($semicolon eq ';');
		}
		elsif ($key eq 'otherBackupSeries')
		{
		    $printNextLine = 0;
		    print FILE join("\n", @comments),
		    "\n$key=0:$series\n";
		    $prLog->print('-kind' => 'I',
				  '-str' =>
         		  ["$generateConfigFile: setting <$key> to 0:$series"]);
		}	      
		elsif ($key eq 'lateLinks')
		{
		    $printNextLine = 1;
		    print FILE join("\n", @comments),
		    "\n$key=yes\n";
		    $prLog->print('-kind' => 'I',
				  '-str' =>
		      ["$generateConfigFile: changed <$key> to 'yes'"])
			unless $lateLinks;
		    delete $checkKeys{$key};
		}
		elsif ($key eq 'lateCompress')
		{
		    $printNextLine = 1;
		    print FILE join("\n", @comments),
		    "\n$semicolon$key=$line\n";
		    $prLog->print('-kind' => 'I',
				  '-str' =>
		      ["$generateConfigFile: you may want to change <$key> " .
		       "to 'no'"])
			if $lateCompress;
		}
		elsif ($key eq 'keepMinNumber')
		{
		    $printNextLine = 0;
		    print FILE join("\n", @comments),
		    "\n$key=99999\n";
		}
		elsif ($key =~ /\Akeep/)
		{
		    $printNextLine = 0;
		    print FILE join("\n", @comments),
		    "\n;$key=$line\n";
		}
		else
		{
		    $printNextLine = 1;
		    print FILE join("\n", @comments), "\n$semicolon$key=$line\n";
		}

		(@comments) = ();
	    }
	    else
	    {
		die "cannot identify line $i in file $configFile:\n<",
		$configFile[$i-1], ">\n";
	    }
	}
    }
    close(FILE);

    $prLog->print('-kind' => 'E',
		  '-str' => ["$generateConfigFile: couldn't find key(s) <" .
			     join('> <', sort keys %checkKeys) . ">"],
		  '-exit' => 1)
	if scalar(keys %checkKeys);
}


#
# copy main special files and directory structure
#
unless (-d $targetSeriesDir)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot create directory <$targetSeriesDir>"],
		  '-exit' => 1)
	unless mkdir $targetSeriesDir, 0755;
}

$lastBackupDir =~ m#.*/(.+)#;
my $targetBackupDir = "$targetSeriesDir/$1";
mkdir $targetBackupDir;

$prLog->print('-kind' => 'I',
	      '-str' => ["created directory <$targetBackupDir>"])
    if $verbose;

&::copyStbuSpecialFiles($lastBackupDir, $targetBackupDir, $prLog, $verbose,
			'/tmp');

$prLog->print('-kind' => 'I',
	      '-str' =>
	      ["you may want to adjust <$generateConfigFile> to your needs"])
    if ($configFile and not $useOldConfig);


exit 0;

