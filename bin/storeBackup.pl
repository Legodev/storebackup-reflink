#!/usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2001-2014)
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

require SDBM_File;
require Tie::Hash;

use Fcntl qw(O_RDWR O_CREAT);
use IO::Compress::Gzip qw(gzip $GzipError);
use POSIX;
use Digest::MD5 qw(md5_hex);

use strict;
use warnings;

$main::STOREBACKUPVERSION = undef;


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

require 'storeBackupGlob.pl';
require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'splitLine.pl';
require 'fileDir.pl';
require 'dateTools.pl';
require 'forkProc.pl';
require 'humanRead.pl';
require 'version.pl';
require 'evalTools.pl';
require 'storeBackupLib.pl';

no warnings 'newline';    # no warning for stat of files with newline
                          # works in perl 5.6+ only

#/usr/include/linux/limits.h:#define ARG_MAX       131072        /* #
#bytes of args + environ for exec() */
#
#
#Aus dem Source für "xargs" geht hervor:
#
#  orig_arg_max = ARG_MAX - 2048; /* POSIX.2 requires subtracting 2048. */
#  arg_max = orig_arg_max;

$main::stbuMd5Exec = "$req/stbuMd5Exec.pl";
$main::stbuMd5cp = "$req/stbuMd5cp.pl";
$main::endOfStoreBackup = 0;
$main::execParamLength = 4 * 1024;      # Default Wert, sehr niedrig angesetzt
$main::minCopyWithFork = 1024**2;       # alles was <= ist, wird in perl
                                        # kopiert, was > ist, mit fork
my (%execParamLength) = ('AIX' => 22 * 1024,
			 'Linux' => 62 * 1024);
$main::sourceDir = '';                  # set for main::COMRESS
                                        # path to backup directory


my $storeBackupUpdateBackup_prg = 'storeBackupUpdateBackup.pl';
my $lockFile = '/tmp/storeBackup.lock';   # default value
my (@compress) = ('bzip2');               # default value
my (@uncompress) = ('bzip2', '-d');       # default value
my $minCompressSize = 1024;       # default value
my $postfix = '.bz2';             # default value
my $queueCompress = 1000;         # default value
my $queueCopy = 1000;             # default value
my $queueBlock = 1000;            # default value
my $noBlockRules = 5;             # default value, must be > 0
$main::noBlockDevices = 5;        # default value, must be > 0
$main::noCompressRules = 5;       # default value, must be > 0
my $checkBlocksBSdefault = '1M';  # default value
my $checkBlocksBSmin = 10*1024;   # minimal value
my $noCopy = 1;                   # default value
my $chmodMD5File = '0600';        # default value
my $tmpdir = '/tmp';              # default value
my @exceptSuffix = ('\.zip', '\.bz2', '\.gz', '\.tgz', '\.jpg', '\.gif',
		    '\.tiff?', '\.mpe?g', '\.mp[34]', '\.mpe?[34]', '\.ogg',
		    '\.gpg', '\.png', '\.lzma', '\.xz', '\.mov');
my $logInBackupDirFileName = '.storeBackup.log';
my $checkSumFile = '.md5CheckSums';
my $blockCheckSumFile = '.md5BlockCheckSums';
$main::checkSumFileVersion = '1.3';
my $keepAll = '30d';
my $keepDuplicate = '7d';

my $flagBlockDevice = 0;          # 1 if block or device options are used
$tmpdir = $ENV{'TMPDIR'} if defined $ENV{'TMPDIR'};


# storeBackup.pl $main::STOREBACKUPVERSION

=head1 NAME

storeBackup.pl - fancy compressing managing checksumming
                 hard-linking deduplicating 'cp -ua'

=head1 DESCRIPTION

This program copies trees to another location. Every file copied is
potentially compressed (see --exceptSuffix). The backups after
the first backup will compare the files with an md5 checksum
with the last stored version. If they are equal, it will only make an
hard link to it. It will also check mtime, ctime and size to recognize
idential files in older backups very fast.
It can also backup big image files fast and efficiently on a per block
basis (data deduplication).

You can overwrite options in the configuration file on the command line.

=head1 SYNOPSIS

	storeBackup.pl --help
or    
	storeBackup.pl -g configFile
or
	storeBackup.pl [-f configFile] [-s sourceDir]
	      [-b backupDirectory] [-S series] [--checkCompr] [--print]
	      [-T tmpdir] [-L lockFile] [--unlockBeforeDel] 
	      [--exceptDirs dir1] [--contExceptDirsErr]
	      [--includeDirs dir1]
	      [--exceptRule rule] [--includeRule rule]
	      [--exceptTypes types]
	      [--specialTypeArchiver archiver [--archiveTypes types]]
	      [--cpIsGnu] [--linkSymlinks]
	      [--precommand job] [--postcommand job]
              [--followLinks depth] [--stayInFileSystem] [--highLatency]
	      [--ignorePerms] [--lateLinks [--lateCompress]] [--autorepair]
	      [--checkBlocksSuffix suffix] [--checkBlocksMinSize size]
	      [--checkBlocksBS] [--checkBlocksCompr check|yes|no]
	      [--checkBlocksParallel] [--queueBlock]
              [--checkBlocksRule0 rule [--checkBlocksBS0 size]
               [--checkBlocksCompr0 key] [--checkBlocksRead0 filter]
               [--checkBlocksParallel0]]
              [--checkBlocksRule1 rule [--checkBlocksBS1 size]
               [--checkBlocksCompr1 key] [--checkBlocksRead1 filter]
               [--checkBlocksParallel1]]
              [--checkBlocksRule2 rule [--checkBlocksBS2 size]
               [--checkBlocksCompr2 kdey] [--checkBlocksRead2 filter]
               [--checkBlocksParallel2]]
              [--checkBlocksRule3 rule [--checkBlocksBS3 size]
               [--checkBlocksCompr3 key] [--checkBlocksRead3 filter]
               [--checkBlocksParallel3]]
              [--checkBlocksRule4 rule [--checkBlocksBS4 size]
               [--checkBlocksCompr4 key] [--checkBlocksRead4 filter]
               [--checkBlocksParallel4]]
              [--checkDevices0 list [--checkDevicesDir0]
               [--checkDevicesBS0] [checkDevicesCompr0 key]
               [--checkDevicesParallel0]]
              [--checkDevices1 list [--checkDevicesDir1]
               [--checkDevicesBS1] [checkDevicesCompr1 key]
               [--checkDevicesParallel1]]
              [--checkDevices2 list [--checkDevicesDir2]
               [--checkDevicesBS2] [checkDevicesCompr2 key]
               [--checkDevicesParallel2]]
              [--checkDevices3 list [--checkDevicesDir3]
               [--checkDevicesBS3] [checkDevicesCompr3 key]
               [--checkDevicesParallel3]]
              [--checkDevices4 list [--checkDevicesDir4]
               [--checkDevicesBS4] [checkDevicesCompr4 key]
               [--checkDevicesParallel1]]
	      [--saveRAM] [-c compress] [-u uncompress] [-p postfix]
	      [--noCompress number] [--queueCompress number]
	      [--noCopy number] [--queueCopy number]
	      [--withUserGroupStat] [--userGroupStatFile filename]
	      [--exceptSuffix suffixes]	[--addExceptSuffix suffixes]
	      [--compressSuffix] [--minCompressSize size] [--comprRule]
	      [--doNotCompressMD5File] [--chmodMD5File] [-v]
	      [-d level] [--progressReport number[,timeframe]]
	      [--ignoreReadError]
              [--suppressWarning key] [--linkToRecent name]
	      [--doNotDelete] [--deleteNotFinishedDirs]
	      [--resetAtime] [--keepAll timePeriod] [--keepWeekday entry]
	      [[--keepFirstOfYear] [--keepLastOfYear]
	       [--keepFirstOfMonth] [--keepLastOfMonth]
	       [--firstDayOfWeek day] [--keepFirstOfWeek]
               [--keepLastOfWeek] [--keepDuplicate] [--keepMinNumber]
               [--keepMaxNumber]
	        | [--keepRelative] ]
	      [-l logFile
	       [--plusLogStdout] [--suppressTime] [-m maxFilelen]
	       [[-n noOfOldFiles] | [--saveLogs]]
	       [--compressWith compressprog]]
	      [--logInBackupDir [--compressLogInBackupDir]
	       [--logInBackupDirFileName logFile]]
	      [otherBackupSeries ...]


=head1 OPTIONS

=over 8

=item B<--help>

    show this help

=item B<--generate>, B<-g>

    generate a template of the configuration file

=item B<--checkCompr>, B<-C>

    check compression for all files bigger than 1k to check if
    it makes sense to compress them
    overwrites options
        exceptSuffix, addExceptSuffix, minCompressSize, comprRule

=item B<--print>

    print configuration read from configuration file
    or command line and stop

=item B<--file>, B<-f>

    configuration file (instead of or additionally to options
    on command line)

=item B<--sourceDir>, B<-s>

    source directory (must exist)

=item B<--backupDir>, B<-b>

    top level directory of all backups (must exist)

=item B<--series>, B<-S>

    series directory, default is 'default'
    relative path from backupDir

=item B<--tmpdir>, B<-T>

    directory for temporary files, default is </tmp>

=item B<--lockFile>, B<-L>

    lock file, if exists, new instances will finish if an old
    is already running, default is $lockFile
    this type of lock files does not work across multiple servers
    and is not designed to separate storeBackup.pl and
    storeBackupUpdateBackup.pl or any other storeBackup
    process in a separate PID space

=item B<--unlockBeforeDel>

    remove the lock file before deleting old backups
    default is to delete the lock file after removing old
    backups

=item B<--exceptDirs>, B<-e>

    directories to except from backing up (relative path),
    wildcards are possible and should be quoted to avoid
    replacements by the shell
    use this parameter multiple times for multiple
    directories

=item B<--contExceptDirsErr>

    continue if one or more of the exceptional directories
    do not exist (default is to stop processing)

=item B<--includeDirs>, B<-i>

    directories to include in the backup (relative path),
    wildcards are possible and have to be quoted
    use this parameter multiple times for multiple directories

=item B<--exceptRule>

    Files to exclude from backing up.
    see README: 'including / excluding files and directories'

=item B<--includeRule>

    Files to include in the backug up - like exceptRule
    see README: 'including / excluding files and directories'

=item B<--writeExcludeLog>

    write a file name .storeBackup.notSaved.bz2 with the names
    of all skipped files

=item B<--exceptTypes>

    do not save the specified type of files, allowed: Sbcfpl
        S - file is a socket
        b - file is a block special file
        c - file is a character special file
        f - file is a plain file
        p - file is a named pipe
        l - file is a symbolic link
        Sbc can only be saved when using option [cpIsGnu]

=item B<--archiveTypes>

    save the specified type of files in an archive instead saving
    them directly in the file system
    use this if you want to backup those file types but your target
    file or transport (eg. sshfs or non gnu-cp) system does not support
    those types of files
        S - file is a socket
        b - file is a block special file
        c - file is a character special file
        p - file is a named pipe
    you also have to set --specialTypeArchiver when using this option

=item B<--specialTypeArchiver>

    possible values are 'cpio' or 'tar'. default is 'cpio'
    tar is not able to archive sockets
    cpio is not part of the actual posix standard any more

=item B<--cpIsGnu>

    Activate this option if your systems cp is a full-featured
    GNU version. In this case you will be able to also backup
    several special file types like sockets.

=item B<--linkSymlinks>

    hard link identical symlinks

=item B<--precommand>

    exec job before starting the backup, checks lockFile (-L)
    before starting (e.g. can be used for rsync)
    stops execution if job returns exit status != 0
    This parameter is parsed like a line in the configuration
    file and normally has to be quoted.

=item B<--postcommand>

    exec job after finishing the backup, but before erasing of
    old backups  reports if job returns exit status != 0
    This parameter is parsed like a line in the configuration
    file and normally has to be quoted.

=item B<--followLinks>

    follow symbolic links like directories up to depth
    default = 0 -> do not follow links

=item B<--stayInFileSystem>

    only store the contents of file systems named by
    --sourceDir and symlinked via --followLinks

=item B<--highLatency>

    use this for a very high latency line (eg. vpn over
    the internet) for better parallelization

=item B<--ignorePerms>

    If this option choosen, files will not necessarily have
    the same permissions and owner as the originals. This
    speeds up backups on network drives a lot. Recovery with
    storeBackupRecover.pl will restore them correctly.

=item B<--lateLinks>

    do *not* write hard links to existing files in the backup
    during the backup
    you have to call the program storeBackupWriteLateLink.pl
    later on your server if you set this flag to 'yes'
    you have to run storeBackupUpdateBackup.pl later - see
    description for that program

=item B<--lateCompress>

    only in combination with --lateLinks
    compression from files >= minCompressSize will be done
    later, the file is (temporarily) copied into the backup

=item B<--autorepair>, B<-a>

    repair simple inconsistencies (from lateLinks) automatically
    without requesting the action

=item B<--checkBlocksSuffix>

    Files with suffix for which storeBackup will make an md5
    check on blocks of that file. Executed after
    --checkBlocksRule(n)
    This option can be repeated multiple times

=item B<--checkBlocksMinSize>

    Only check files specified in --checkBlocksSuffix if there
    file size is at least this value, default is 100M

=item B<--checkBlocksBS>

    Block size for files specified with --checkBlocksSuffix
    Default is $checkBlocksBSdefault (1 megabyte)

=item B<--checkBlocksCompr>

    if set, the blocks generated due to checkBlocksSuffix
    are compressed, default is 'no'
    if set to 'check', tries to estimate if compression helps

=item B<--checkBlocksParallel>

    Read files specified here in parallel to "normal" ones.
    This only makes sense if they are on a different disk.
    Default value is 'no'

=item B<--queueBlock>

    length of queue to store files before block checking,
    default = $queueBlock

=item B<--checkBlocksRule0>

    Files for which storeBackup will make an md5 check
    depending on blocks of that file.

=item B<--checkBlocksBS0>

    Block size for option checkBlocksRule
    Default is $checkBlocksBSdefault (1 megabyte)

=item B<--checkBlocksCompr0>

    if set, the blocks generated due to this rule are
    compressed

=item B<--checkBlocksRead0>

    Filter for reading the file to treat as a blocked file
    eg. 'gzip -d' if the file is compressed. Default is no
    read filter.
    This parameter is parsed like the line in the
    configuration file and normally has to be quoted,
    eg. 'gzip -9'

=item B<--checkBlocksParallel0>

    Read files specified here in parallel to "normal" ones.
    This only makes sense if they are on a different disk.
    Default value is 'no'

=item B<--checkBlocksRule1>

=item B<--checkBlocksBS1>

=item B<--checkBlocksCompr1>

=item B<--checkBlocksRead1>

=item B<--checkBlocksParallel1>

=item B<--checkBlocksRule2>

=item B<--checkBlocksBS2>

=item B<--checkBlocksCompr2>

=item B<--checkBlocksRead2>

=item B<--checkBlocksParallel2>

=item B<--checkBlocksRule3>

=item B<--checkBlocksBS3>

=item B<--checkBlocksCompr3>

=item B<--checkBlocksRead3>

=item B<--checkBlocksParallel3>

=item B<--checkBlocksRule4>

=item B<--checkBlocksBS4>

=item B<--checkBlocksCompr4>

=item B<--checkBlocksRead4>

=item B<--checkBlocksParallel4>

=item B<--checkDevices0>

    List of devices for md5 ckeck depending on blocks of these
    devices (eg. /dev/sdb or /dev/sdb1)

=item B<--checkDevicesDir0>

    Directory where to store the backup of the device

=item B<--checkDevicesBS0>

    Block size of option checkDevices0,
    default is 1M (1 megabyte)

=item B<--checkDevicesCompr0>

    Compress blocks resulting from option checkDevices0
    possible values are 'check', 'yes' or 'no', default is 'no'

=item B<--checkDevicesParallel0>

    Read devices specified in parallel to the rest of the
    backup. This only makes sense if they are on a different
    disk. Default value is 'no'

=item B<--checkDevices1>

=item B<--checkDevicesDir1>

=item B<--checkDevicesBS1>

=item B<--checkDevicesCompr1>

=item B<--checkDevicesParallel1>

=item B<--checkDevices2>

=item B<--checkDevicesDir2>

=item B<--checkDevicesBS2>

=item B<--checkDevicesCompr2>

=item B<--checkDevicesParallel2>

=item B<--checkDevices3>

=item B<--checkDevicesDir3>

=item B<--checkDevicesBS3>

=item B<--checkDevicesCompr3>

=item B<--checkDevicesParallel3>

=item B<--checkDevices4>

=item B<--checkDevicesDir4>

=item B<--checkDevicesBS4>

=item B<--checkDevicesCompr4>

=item B<--checkDevicesParallel4>

=item B<--saveRAM>

    write temporary dbm files in --tmpdir
    use this if you do not have enough RAM

=item B<--compress>, B<-c>

    compress command (with options), default is <bzip2>
    This parameter is parsed like the line in the
    configuration file and normally has to be quoted,
    eg. 'gzip -9'

=item B<--uncompress>, B<-u>

    uncompress command (with options), default is  <bzip2 -d>
    This parameter is parsed like the line in the
    configuration file and normally has to be quoted, eg.
    'gzip -d'

=item B<--postfix>, B<-p>

    postfix to add after compression, default is <.bz2>

=item B<--exceptSuffix>

    do not compress files with the following
    suffix (uppercase included):
    '\.zip', '\.bz2', '\.gz', '\.tgz', '\.jpg', '\.gif',
    '\.tiff?', '\.mpeg', '\.mpe?g', '\.mpe?[34]', '\.ogg',
    '\.gpg', '\.png', '\.lzma', '\.xz', '\.mov'
    This option can be repeated multiple times
    If you do not want any compression, set this option
    to '.*'

=item B<--addExceptSuffix>

    like --exceptSuffix, but do not replace defaults, add

=item B<--compressSuffix>

    Like --exceptSuffix, but mentioned files will be
    compressed. If you chose this option, then files not
    affected be execptSuffix, addExceptSuffix or this Suffixes
    will be rated by the rule function COMPRESSION_CHECK wether
    to compress or not

=item B<--minCompressSize>

    Files smaller than this size will never be compressed
    but copied

=item B<--comprRule>

    alternative to --exceptSuffix, compressSuffix and minCompressSize:
    definition of a rule which files will be compressed

=item B<--noCompress>

    maximal number of parallel compress operations,
    default = choosen automatically

=item B<--queueCompress>

    length of queue to store files before compression,
    default = 1000

=item B<--noCopy>

    maximal number of parallel copy operations,
    default = 1

=item B<--queueCopy>

    length of queue to store files before copying,
    default = 1000

=item B<--withUserGroupStat>

    write statistics about used space in log file

=item B<--userGroupStatFile>

    write statistics about used space in name file
    will be overridden each time

=item B<--doNotCompressMD5File>

    do not compress .md5CheckSumFile

=item B<--chmodMD5File>

    permissions of .md5CheckSumFile and corresponding
    .storeBackupLinks directory, default is 0600

=item B<--verbose>, B<-v>

    verbose messages

=item B<--debug>, B<-d>

    generate debug messages, levels are 0 (none, default),
    1 (some), 2 (many) messages, especially in
    --exceptRule and --includeRule

=item B<--resetAtime>

    reset access time in the source directory - but this will
    change ctime (time of last modification of file status
    information)

=item B<--doNotDelete>

    check only, do not delete any backup

=item B<--deleteNotFinishedDirs>

    delete old backups which have not been finished
    this will only happen if doNotDelete is set

=item B<--keepAll>

    keep backups which are not older than the specified amount
    of time. This is like a default value for all days in
    --keepWeekday. Begins deleting at the end of the script
    the time range has to be specified in format 'dhms', e.g.
      10d4h means 10 days and 4 hours
      default = 20d

=item B<--keepWeekday>

    keep backups for the specified days for the specified
    amount of time. Overwrites the default values choosen in
    --keepAll. 'Mon,Wed:40d Sat:60d10m' means:
      keep backups from Mon and Wed 40days + 5mins
      keep backups from Sat 60days + 10mins
      keep backups from the rest of the days like spcified in
      --keepAll (default $keepAll)
    if you also use the 'archive flag' it means to not
    delete the affected directories via --keepMaxNumber:
      a10d4h means 10 days and 4 hours and 'archive flag'
    e.g. 'Mon,Wed:a40d5m Sat:60d10m' means:
      keep backups from Mon and Wed 40days + 5mins + 'archive'
      keep backups from Sat 60days + 10mins
      keep backups from the rest of the days like specified in
      --keepAll (default 30d)

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
    default = 7d

=item B<--keepMinNumber>

    Keep that miminum of backups. Multiple backups of one
    day are counted as one backup. Default is 10.

=item B<--keepMaxNumber>

    Try to keep only that maximum of backups. If you have more
    backups, the following sequence of deleting will happen:
    - delete all duplicates of a day, beginning with the old
      once, except the last of every day
    - if this is not enough, delete the rest of the backups
      beginning with the oldest, but *never* a backup with
      the 'archive flag' or the last backup

=item B<--keepRelative>, B<-R>

    Alternative deletion scheme. If you use this option, all
    other keep options are ignored. Preserves backups depending
    on their *relative* age. Example:
    -R '1d 7d 61d 92b'
    will (try to) ensure that there is always
    - One backup between 1 day and 7 days old
    - One backup between 5 days and 2 months old
    - One backup between ~2 months and ~3 months old
    If there is no backup for a specified timespan
    (e.g. because the last backup was done more than 2 weeks
    ago) the next older backup will be used for this timespan.

=item B<--progressReport>, B<-P>

    print progress report after each 'number' files
    additional you may add a time frame after which a message is
    printed
    if you want to print a report each 1000 files and after
    one minute and 10 seconds, use: -P 1000,1m10s

=item B<--printDepth>, B<-D>

    print depth of actual read directory during backup

=item B<--ignoreReadError>

    ignore read errors in source directory; not readable
    directories do not cause storeBackup.pl to stop processing

=item B<--suppressWarning>

    suppress (unwanted) warnings in the log files;
    to suppress warnings, the following keys can be used:
      excDir (suppresses the warning that excluded directories
             do not exist)
      fileChange (suppresses the warning that a file has changed
                 during the backup)
      crSeries (suppresses the warning that storeBackup had to
               create the 'default' series)
      hashCollision (suppresses the warning if a possible
                    hash collision is detected)
     fileNameWithLineFeed (suppresses the warning if a filename
                          contains a line feed)
     use_DB_File (suppresses the warning that you should install
                  perl module DB_File for better perforamnce)
     use_MLDBM (suppresses the warning that you should install
                perl module MLDBM if you want to use rule functions
                MARK_DIR or MARK_DIR_REC together with option saveRAM)
     use_IOCompressBzip2 (suppresses the warning that you should
                          instal perl module IO::Compress::Bzip2
                          for better performance)
     noBackupForPeriod (suppresses warning that there are
                        no backups for certain periods when using
                        option keepRelative)
    This option can be repeated multiple times on the command line.

=item B<--linkToRecent>

    after a successful backup, set a symbolic link to
    that backup and delete existing older links with the
    same name

=item B<--logFile>, B<-l>

    log file (default is STDOUT)

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

    compress saved log files (e.g. with 'gzip -9')
    default is 'bzip2'
    This parameter is parsed like a line in the configuration
    file and normally has to be quoted.

=item B<--logInBackupDir>

    write log file (also) in the backup directory
    Be aware that this log does not contain all error
    messages of the one specified with --logFile!

=item B<--compressLogInBackupDir>

    compress the log file in the backup directory

=item B<--logInBackupDirFileName>

    filename to use for writing the above log file,
    default is .storeBackup.log

=item B<otherBackupSeries>

    List of other backup series to consider for
    hard linking. Relative path from backupDir!
    Format (examples):
    backupSeries/2002.08.29_08.25.28 -> consider this backup
    or
    0:backupSeries ->last (youngest) in <backupDir>/backupSeries
    1:backupSeries ->one before last in <backupDir>/backupSeries
    n:backupSeries ->
      n'th before last in <backupDir>/backupSeries
    3-5:backupSeries ->
      3rd, 4th and 5th in <backupDir>/backupSeries
    all:backupSeries -> all in <backupDir>/backupSeries
    You can also use wildcards in series names. See documentation,
    section 'Using Wildcards for Replication' for details.
    Default is to link to the last backup in every series

=back

=head1 COPYRIGHT

Copyright (c) 2000-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License, either version 3
of the License, or (at your option) any later version.

=cut

my $Help = <<EOH;
try '$prog --help' to get a description of the options.
EOH
    ;
# '

my $FullHelp = &::getPod2Text($0);

my $blockRulesHelp = <<EOH;
# Files for which storeBackup will make an md5 check depending
# on blocks of that file.
# The rules are checked from rule 1 to rule 5. The first match is used
# !!! see README file 'including / excluding files and directories'
# EXAMPLE: 
# searchRule = ( '\$size > &::SIZE("3M")' and '\$uid eq "hjc"' ) or
#    ( '\$mtime > &::DATE("3d4h")' and not '\$file =~ m#/tmp/#' )'
;checkBlocksRule0=

# Block size for option checkBlocksRule
# default is $checkBlocksBSdefault (1 megabyte)
;checkBlocksBS0=

# if set to 'yes', blocks generated due to this rule will be compressed
# possible values: 'check', 'yes' or 'no', default is 'no'
# check users COMRESSION_CHECK (see option compressSuffix)
;checkBlocksCompr0=

# Filter for reading the file to treat as a blocked file
# eg.   gzip -d   if the file is compressed. Default is no read filter.
;checkBlocksRead0=

# Read files specified here in parallel to "normal" ones.
# This only makes sense if they are on a different disk.
# Default value is 'no'
;checkBlocksParallel0=

EOH
    ;
{
    my $i;
    foreach $i (1..$noBlockRules-1)
    {
	$blockRulesHelp .=
	    sprintf(";checkBlocksRule%d=\n;checkBlocksBS%d=\n;checkBlocksCompr%d=\n" .
		    ";checkBlocksRead%d=\n;checkBlocksParallel%d=\n\n",
		    $i, $i, $i, $i, $i);
    }
    chop $blockRulesHelp;
}

my $blockDeviceHelp = <<EOH;
#  List of Devices for md5 ckeck depending on blocks of these
#  Devices (eg. /dev/sdb or /dev/sdb1)
;checkDevices0=

# Directory where to store the backups of the devices
;checkDevicesDir0=

# Block size of option checkDevices0
# default is $checkBlocksBSdefault (1 megabyte)
;checkDevicesBS0=

# if set, the blocks generated due to checkDevices0 are compressed
# possible values: 'check', 'yes' or 'no', default is 'no'
# check users COMRESSION_CHECK (see option compressSuffix)
;checkDevicesCompr0=

# Read devices specified here in parallel to "normal" ones.
# This only makes sense if they are on a different disk.
# Default value is 'no'
;checkDevicesParallel0=

EOH
    ;
{
    my $i;
    foreach $i (1..$main::noBlockDevices-1)
    {
	$blockDeviceHelp .=
	    sprintf(";checkDevices%d=\n;checkDevicesDir%d=\n" .
		    ";checkDevicesBS%d=\n;checkDevicesCompr%d=\n" .
		    ";checkDevicesParallel%d=\n\n",
		    $i, $i, $i, $i, $i);
    }
    chop $blockDeviceHelp;
}

my $compressRuleHelp = <<EOH;
# external command (with options) for compression (or something else)
# explanation see compressRule0 below
;compress0=

# external uncompress command (with options), must fit to compress0
# explanation see compressRule0 below
;uncompress0=

# postfix for command quoted at compress0 above
# explanation see compressRule0 below
;postfix0=

# Rule for calling an external program on each file.
# This can be done with different compression programs or
# eg. with encryption programs.
# The rules are operated from rule 0 to rule 4 - if none
# of these rules fits, compress which depends on
# exceptSuffix, addExceptSuffix or comprRule is used.
;compressRule0=

EOH
    ;

{
    my $i;
    foreach $i (1..$main::noCompressRules-1)
    {
	$compressRuleHelp .=
	    sprintf(";compress%d=\n;uncompress%d=\n" .
		    ";postfix%d=\n;compressRule%d=\n\n",
		    $i, $i, $i, $i);
    }
    chop $compressRuleHelp;
}

my $templateConfigFile = <<EOC;
# configuration file for storeBackup.pl
# Generated by storeBackup.pl, $main::STOREBACKUPVERSION

####################
### explanations ###
####################

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
# If you want the default value, comment it:
;logFile =
# You can also use environment variables, like \$XXX or \${XXX} like in
# a shell. Single quotes will mask environment variables, while double
# quotes will not.
# You can mask \$, {, }, ", ' with a backslash (\\), eg. \\\$
# Lines beginning with a '#' or ';' are ignored (use this for comments)
#
# You can overwrite settings in the command line. You can remove
# the setting also in the command by using the --unset feature, eg.:
# '--unset doNotDelete' or '--unset --doNotDelete'

#####################
### configuration ###
#####################

# source directory (*** must be specified ***)
;sourceDir=

# top level directory of all linked backups (*** must be specified ***)
# storeBackup must know for consistency checking where all your backups
# are. This is done to make sure that your backups are consistent if you
# used --lateLinks.
;backupDir=

# ------------------------------------------------------------------------
# you do not need specify the options below to get a running configuration
# (but they give you more features and more control)
#


# series directory, default is 'default'
# relative path from backupDir
;series=

# directory for temporary file, default is /tmp
;tmpDir=

# List of other backup directories to consider for
# hard linking. Relative path from backupDir!
# Format (examples):
# backupSeries/2002.08.29_08.25.28 -> consider this backup
# or
# 0:backupSeries    -> last (youngest) backup in <backupDir>/backupSeries
# 1:backupSeries    -> first before last backup in <backupDir>/backupSeries
# n:backupSeries    -> n'th before last backup in <backupDir>/backupSeries
# 3-5:backupSeries  -> 3rd, 4th and 5th in <backupDir>/backupSeries
# all:backupSeries  -> all in <backupDir>/backupSeries
# This option is useful, if you want to explicitly hard link
# to backup series from different backups. You can specify eg. with
# 0:myBackup to the last backup of series 'myBackup'. If you specify
# backup series with otherBackupSeries, then only these backups will be
# used for hard linking.
# You can also use wildcards in series names. See documentation,
# section 'Using Wildcards for Replication' for details.
# Default value is to link to the last backup of all series stored in
# 'backupDir'.
;otherBackupSeries=

# lock file, if exist, new instances will finish if
# an old is already running, default is $lockFile
;lockFile=

# remove the lock files before deleting old backups
# default ('no') is to delete the lock file after deleting
# possible values are 'yes' and 'no'
;unlockBeforeDel=

# continue if one or more of the exceptional directories
# do not exist (no is stopping processing)
# default is 'no', can be 'yes' or 'no'
;contExceptDirsErr=

# Directories to exclude from the backup (relative path inside of the backup).
# You can use shell type wildcards.
# These directories have to be separated by space or newline.
;exceptDirs=

# Directories to include in the backup (relative path inside of the backup).
# You can use shell type wildcards.
# These directories have to be separated by space or newline.
;includeDirs=

# rule for excluding files / only for experienced administrators
# !!! see README file 'including / excluding files and directories'
# EXAMPLE: 
# searchRule = ( '\$size > &::SIZE("3M")' and '\$uid eq "hjc"' ) or
#    ( '\$mtime > &::DATE("3d4h")' and not '\$file =~ m#/tmp/#' )'
;exceptRule=

# For explanations, see 'exceptRule'.
;includeRule=

# write a file name .storeBackup.notSaved.bz2 with the
# names of all skipped files, default is 'no', can be 'yes' or 'no'
;writeExcludeLog=

# do not save the specified types of files, allowed: Sbcfpl
# S - file is a socket
# b - file is a block special file
# c - file is a character special file
# f - file is a plain file
# p - file is a named pipe
# l - file is a symbolic link
# Spbc can only be backed up if GNU copy is available.
;exceptTypes=

# save the specified type of files in an archive instead saving
# them directly in the file system
# use this if you want to backup those file types but your target
# file or transport (eg. sshfs or non gnu-cp) system does not support
# those types of file
#   S - file is a socket
#   b - file is a block special file
#   c - file is a character special file
#   p - file is a named pipe
#   l - file is a symbolic link
# you also have to set specialTypeArchiver when using this option
;archiveTypes=


# possible values are 'cpio', 'tar', 'none'. default is 'cpio'
# tar is not able to archive sockets
# cpio is not part of the actual posix standard any more
;specialTypeArchiver=

# Activate this option if your system's cp is a full-featured GNU
# version. In this case you will be able to also backup several
# special file types like sockets.
# Possible values are 'yes' and 'no'. Default is 'no'
;cpIsGnu=

# make a hard link to existing, identical symlinks in old backups
# use this, if your operating system supports this (linux does)
# Possible values are 'yes' and 'no'. Default is 'no'
;linkSymlinks=

# exec job before starting the backup, checks lockFile (-L) before
# starting (e.g. can be used for rsync) stops execution if job returns
# exit status != 0
;precommand=

# exec job after finishing the backup, but before erasing of old
# backups reports if job returns exit status != 0
;postcommand=

# follow symbolic links like directories up to depth 0 -> do not
# follow links
;followLinks=

# only store the contents of file systems named by
# sourceDir and symlinked via followLinks
# possible values are 'yes' and 'no'; default is 'no'
;stayInFileSystem=

# use this only if you write your backup over a high latency line
# like a vpn over the internet
# storebackup will use more parallelization at the cost of more
# cpu power
# possible values are 'yes' and 'no'; default is 'no'
;highLatency=

# If this option is disabled, then the files in the backup will not
# neccessarily have the same permissions and owner as the originals.
# This speeds up backups on network drives a lot. Correct permissions
# are restored by storeBackupRecover.pl no matter what this option is
# set to. Default is 'no'
;ignorePerms=

# suppress (unwanted) warnings in the log files;
# to suppress warnings, the following keys can be used:
#   excDir (suppresses the warning that excluded directories
#          do not exist)
#   fileChange (suppresses the warning that a file has changed during
#              the backup)
#   crSeries (suppresses the warning that storeBackup had to create the
#            'default' series)
#   hashCollision (suppresses the warning if a possible
#                 hash collision is detected)
#   fileNameWithLineFeed (suppresses the warning if a filename
#                        contains a line feed)
#    use_DB_File (suppresses the warning that you should install
#                 perl module DB_File for better perforamnce)
#    use_MLDBM (suppresses the warning that you should install
#               perl module MLDBM if you want to use rule functions
#               MARK_DIR or MARK_DIR_REC together with option saveRAM)
#    use_IOCompressBzip2 (suppresses the warning that you should
#                         instal perl module IO::Compress::Bzip2
#                         for better performance)
#    noBackupForPeriod (suppresses warning that there are
#                       no backups for certain periods when using
#                       option keepRelative)
#  This option can be repeated multiple times on the command line.
#  Example usage in conf file:
#  suppressWarning = excDir fileChange crSeries hashCollision
#  By default no warnings are suppressed.
;suppressWarning=

# do *not* write hard links to existing files in the backup
# during the backup (yes|no)
# you have to call the program storeBackupUpdateBackup.pl
# later on your server if you set this flag to 'yes'
# you have to run storeBackupUpdateBackup.pl later - see
# description for that program
# default = no: do not write hard links
;lateLinks=

# only in combination with --lateLinks
# compression from files >= size will be done later,
# the file is (temporarily) copied into the backup
# default = no: no late compression
;lateCompress=

# repair simple inconsistencies (from lateLinks) automatically
# without requesting the action
# default = no, no automatic repair
;autorepair=

# Files with specified suffix for which storeBackup will make an md5 check
# on blocks of that file. Executed after --checkBlocksRule(n)
;checkBlocksSuffix=

# Only check files specified in --checkBlocksSuffix if there
# file size is at least this value, default is 100M
;checkBlocksMinSize=

# Block size for files specified with --checkBlocksSuffix
# default is $checkBlocksBSdefault (1 megabyte)
;checkBlocksBS=

# if set, the blocks generated due to checkBlocksSuffix are compressed
# Possible values are 'check, 'yes' and 'no'. Default is 'no'
# check uses COMRESSION_CHECK (see option compressSuffix)
;checkBlocksCompr=

# Read files specified here in parallel to "normal" ones.
# This only makes sense if they are on a different disk.
# Default value is 'no'
;checkBlocksParallel=

# length of queue to store files before block checking,
# default = $queueBlock
;queueBlock=

$blockRulesHelp
$blockDeviceHelp
# write temporary dbm files in --tmpdir
# use this if you have not enough RAM, default is no
;saveRAM=

# compress command (with options), default is <@compress>
;compress=

# uncompress command (with options), default is <@uncompress>
;uncompress=

# postfix to add after compression, default is <$postfix>
;postfix=

# do not compress files with the following
# suffix (uppercase included):
# (if you set this to '.*', no files will be compressed)
# Default is @exceptSuffix
;exceptSuffix=

# like --exceptSuffix, but do not replace defaults, add
;addExceptSuffix=


# Like --exceptSuffix, but mentioned files will be
# compressed. If you chose this option, then files not
# affected be execptSuffix, addExceptSuffix or this Suffixes
# will be rated by the rule function COMPRESS_CHECK wether
# to compress or not
;compressSuffix=

# Files smaller than this size will never be compressed but always
# copied. Default is $minCompressSize
;minCompressSize=

# alternative to exceptSuffix, comprRule and minCompressSize:
# definition of a rule which files will be compressed
# If this rule is set, exceptSuffix, addExceptSuffix
# and minCompressSize are ignored.
# Default rule _generated_ from the options above is:
# comprRule = '\$size > 1024' and not
#   '\$file =~ /\.zip\\Z|\.bz2\\Z|\.gz\\Z|\.tgz\\Z|\.jpg\\Z|\.gif\\Z|\.tiff\\Z|\.tif\\Z|\.mpeg\\Z|\.mpg\\Z|\.mp3\\Z|\.ogg\\Z|\.gpg\\Z|\.png\\Z/i'
# or (eg. if compressSuffix = \.doc \.pdf):
#   '\$size > 1024 and not \$file =~ /\.zip\\Z|\.bz2\\Z|\.gz\\Z|\.tgz\\Z|\.jpg\\Z|\.gif\\Z|\.tiff\\Z|\.tif\\Z|\.mpeg\\Z|\.mpg\\Z|\.mp3\\Z|\.ogg\\Z|\.gpg\\Z|\.png\\Z/i and ( \$file =~ /\.doc\\Z|\.pdf\\Z/i or &::COMPRESSION_CHECK(\$file) )'
;comprRule=

# maximal number of parallel compress operations,
# default = choosen automatically
;noCompress=

# length of queue to store files before compression,
# default = $queueCompress
;queueCompress=

# maximal number of parallel copy operations,
# default = $noCopy
;noCopy=

# length of queue to store files before copying,
# default = $queueCopy
;queueCopy=

# write statistics about used space in log file
# default is 'no'
;withUserGroupStat=

# write statistics about used space in name file
#		    will be overridden each time
# if no file name is given, nothing will be written
# format is:
# identifier uid userName value
# identifier gid groupName value
;userGroupStatFile=

# default is 'no', if you do not want to compress, say 'yes'
;doNotCompressMD5File=

# permissions of .md5checkSumFile, default is $chmodMD5File
;chmodMD5File=

# verbose messages, about exceptRule and includeRule
# and added files. default is 'no'
;verbose=

# generate debug messages, levels are 0 (none, default),
# 1 (some), 2 (many) messages
;debug=

# reset access time in the source directory - but this will
# change ctime (time of last modification of file status
# information
# default is 'no', if you want this, say 'yes'
;resetAtime=

# do not delete any old backup (e.g. specified via --keepAll or
# --keepWeekday) but print a message. This is for testing configuratons
# or if you want to delete old backups with storeBackupDel.pl.
# Values are 'yes' and 'no'. Default is 'no' which means to not delete.
;doNotDelete=

# delete old backups which have not been finished
# this will not happen if doNotDelete is set
# Values are 'yes' and 'no'. Default is 'no' which means not to delete.
;deleteNotFinishedDirs=

# keep backups which are not older than the specified amount
# of time. This is like a default value for all days in
# --keepWeekday. Begins deleting at the end of the script
# the time range has to be specified in format 'dhms', e.g.
# 10d4h means 10 days and 4 hours
# default = $keepAll;
# An archive flag is not possible with this parameter (see below).
;keepAll=

# keep backups for the specified days for the specified
# amount of time. Overwrites the default values choosen in
# --keepAll. 'Mon,Wed:40d Sat:60d10m' means:
# keep backups from Mon and Wed 40days + 5mins
# keep backups from Sat 60days + 10mins
# keep backups from the rest of the days like spcified in
# --keepAll (default $keepAll)
# you can also set the 'archive flag'.
# 'Mon,Wed:a40d5m Sat:60d10m' means:
# keep backups from Mon and Wed 40days + 5mins + 'archive'
# keep backups from Sat 60days + 10mins
# keep backups from the rest of the days like specified in
# --keepAll (default $keepAll)
# If you also use the 'archive flag' it means to not
# delete the affected directories via --keepMaxNumber:
# a10d4h means 10 days and 4 hours and 'archive flag'
;keepWeekday=

# do not delete the first backup of a year
# format is timePeriod with possible 'archive flag'
;keepFirstOfYear=

# do not delete the last backup of a year
# format is timePeriod with possible 'archive flag'
;keepLastOfYear=

# do not delete the first backup of a month
# format is timePeriod with possible 'archive flag'
;keepFirstOfMonth=

# do not delete the last backup of a month
# format is timePeriod with possible 'archive flag'
;keepLastOfMonth=

# default: 'Sun'. This value is used for calculating
# --keepFirstOfWeek and --keepLastOfWeek
;firstDayOfWeek=

# do not delete the first backup of a week
# format is timePeriod with possible 'archive flag'
;keepFirstOfWeek=

# do not delete the last backup of a week
# format is timePeriod with possible 'archive flag'
;keepLastOfWeek=

# keep multiple backups of one day up to timePeriod
# format is timePeriod, 'archive flag' is not possible
# default is $keepDuplicate
;keepDuplicate=

# Keep that miminum of backups. Multiple backups of one
# day are counted as one backup. Default is 10.
;keepMinNumber=

# Try to keep only that maximum of backups. If you have more
# backups, the following sequence of deleting will happen:
# - delete all duplicates of a day, beginning with the old
#   once, except the oldest of every day
# - if this is not enough, delete the rest of the backups
#   beginning with the oldest, but *never* a backup with
#   the 'archive flag' or the last backup
;keepMaxNumber=

# Alternative deletion scheme. If you use this option, all
# other keep options are ignored. Preserves backups depending
# on their *relative* age. Example:
#
#   keepRelative = 1d 7d 61d 92d
#
# will (try to) ensure that there is always
#
# - One backup between 1 day and 7 days old
# - One backup between 5 days and 2 months old
# - One backup between ~2 months and ~3 months old
#
# If there is no backup for a specified timespan (e.g. because the
# last backup was done more than 2 weeks ago) the next older backup
# will be used for this timespan.
;keepRelative =

# print progress report after each 'number' files
# Default is 0, which means no reports.
# additional you may add a time frame after which a message is printed
# if you want to print a report each 1000 files and after
# one minute and 10 seconds, use: -P 1000,1m10s
;progressReport=

# print depth of actual readed directory during backup
# default is 'no', values are 'yes' and 'no'
;printDepth=

# ignore read errors in source directory; not readable
# directories does not cause storeBackup.pl to stop processing
# Values are 'yes' and 'no'. Default is 'no' which means not
# to ignore them
;ignoreReadError=

# after a successful backup, set a symbolic link to
# that backup and delete existing older links with the
# same name
;linkToRecent=

# name of the log file (default is STDOUT)
;logFile=

# if you specify a log file with --logFile you can
# additionally print the output to STDOUT with this flag
# Values are 'yes' and 'no'. Default is 'no'.
;plusLogStdout=

# output in logfile without time: 'yes' or 'no'
# default = no
;suppressTime=

# maximal length of log file, default = 1e6
;maxFilelen=

# number of old log files, default = 5
;noOfOldFiles=

# save log files with date and time instead of deleting the
# old (with [-noOfOldFiles]): 'yes' or 'no', default = 'no'
;saveLogs=

# compress saved log files (e.g. with 'gzip -9')
# default is 'bzip2'
;compressWith=

# write log file (also) in the backup directory:
# 'yes' or 'no', default is 'no'
# Be aware that this log does not contain all error
# messages of the one specified with --logFile!
# Some errors are possible before the backup
# directory is created.
;logInBackupDir=

# compress the log file in the backup directory:
# 'yes' or 'no', default is 'no'
;compressLogInBackupDir=

# filename to use for writing the above log file,
# default is '$logInBackupDirFileName'
;logInBackupDirFileName=

EOC
    ;


&printVersion(\@ARGV, '-V', '--version');

my (@blockRulesOpts);
{
    my $i;
    foreach $i (0..$noBlockRules-1)
    {
	push @blockRulesOpts,
	Option->new('-name' => "checkBlocksRule$i",
		    '-cl_option' => "--checkBlocksRule$i",
		    '-cf_key' => "checkBlocksRule$i",
		    '-quoteEval' => 'yes'),
	Option->new('-name' => "checkBlocksBS$i",
		    '-cl_option' => "--checkBlocksBS$i",
		    '-cf_key' => "checkBlocksBS$i",
		    '-default' => $checkBlocksBSdefault),
	Option->new('-name' => "checkBlocksCompr$i",
		    '-cl_option' => "--checkBlocksCompr$i",
		    '-cf_key' => "checkBlocksCompr$i",
		    '-default' => 'no',
		    '-pattern' => '\Acheck\Z|\Ayes\Z|\Ano\Z'),
	Option->new('-name' => "checkBlocksRead$i",
		    '-cl_option' => "--checkBlocksRead$i",
		    '-cf_key' => "checkBlocksRead$i",
		    '-quoteEval' => 'yes'),
	Option->new('-name' => "checkBlocksParallel$i",
		    '-cl_option' => "--checkBlocksParallel$i",
		    '-cf_key' => "checkBlocksParallel$i",
		    '-cf_noOptSet' => ['yes', 'no']);

    }
}
my (@blockDevicesOpts);
{
    my $i;
    foreach $i (0..$main::noBlockDevices-1)
    {
	push @blockDevicesOpts,
	Option->new('-name' => "checkDevices$i",
		    '-cl_option' => "--checkDevices$i",
		    '-cf_key' => "checkDevices$i",
		    '-multiple' => 'yes'),
	Option->new('-name' => "checkDevicesDir$i",
		    '-cl_option' => "--checkDevicesDir$i",
		    '-cf_key' => "checkDevicesDir$i",
		    '-multiple' => 'yes'),
	Option->new('-name' => "checkDevicesBS$i",
		    '-cl_option' => "--checkDevicesBS$i",
		    '-cf_key' => "checkDevicesBS$i",
		    '-default' => $checkBlocksBSdefault),
	Option->new('-name' => "checkDevicesCompr$i",
		    '-cl_option' => "--checkDevicesCompr$i",
		    '-cf_key' => "checkDevicesCompr$i",
		    '-default' => 'no',
		    '-pattern' => '\Acheck\Z|\Ayes\Z|\Ano\Z'),
	Option->new('-name' => "checkDevicesParallel$i",
		    '-cl_option' => "--checkDevicesParallel$i",
		    '-cf_key' => "checkDevicesParallel$i",
		    '-cf_noOptSet' => ['yes', 'no']);
    }
}

####################!!!!!!!!!!!!!!!!
my (@compressRules);
{
    my $i;

    foreach $i (0..$main::noCompressRules-1)
    {
	push @compressRules,
	Option->new('-name' => "compress$i",
		    '-cl_option' => "--compress$i",
		    '-cf_key' => "compress$i",
		    '-multiple' => 'yes'),
	Option->new('-name' => "uncompress$i",
		    '-cl_option' => "--uncompress$i",
		    '-cf_key' => "uncompress$i",
		    '-multiple' => 'yes'),
	Option->new('-name' => "postfix$i",
		    '-cl_option' => "--postfix$i",
		    '-cf_key' => "postfix$i",
		    '-param' => 'yes'),
	Option->new('-name' => "compressRule$i",
		    '-cl_option' => "--compressRule$i",
		    '-cf_key' => "compressRule$i",
		    '-multiple' => 'yes');
    }
}

my $CheckPar =
    CheckParam->new('-allowLists' => 'yes',
                    '-listMapping' => 'otherBackupSeries',
                    '-configFile' => '-f',
		    '-list' => [Option->new('-name' => 'help',
					    '-cl_option' => '--help'),

                                Option->new('-name' => 'configFile',
					    '-cl_option' => '-f',
					    '-cl_alias' => '--file',
					    '-param' => 'yes',
					    '-only_if' => 'not [generate]'),
                                Option->new('-name' => 'generate',
					    '-cl_option' => '-g',
					    '-cl_alias' => '--generate',
					    '-param' => 'yes',
					    '-only_if' => 'not [configFile]'),
                                Option->new('-name' => 'print',
					    '-cl_option' => '--print',
					    '-only_if' => '[backupDir]'),
                                Option->new('-name' => 'backupDir',
					    '-cl_option' => '-b',
					    '-cl_alias' => '--backupDir',
					    '-cf_key' => 'backupDir',
					    '-param' => 'yes'),
                                Option->new('-name' => 'sourceDir',
					    '-cl_option' => '-s',
					    '-cl_alias' => '--sourceDir',
					    '-cf_key' => 'sourceDir',
					    '-param' => 'yes'),
				Option->new('-name' => 'series',
					    '-cl_option' => '-S',
					    '-cl_alias' => '--series',
					    '-cf_key' => 'series',
					    '-default' => 'default'),
				Option->new('-name' => 'checkCompr',
					    '-cl_option' => '--checkCompr',
					    '-cl_alias' => '-C'),
				Option->new('-name' => 'tmpdir',
					    '-cl_option' => '-T',
					    '-cl_alias' => '--tmpdir',
					    '-cf_key' => 'tmpDir',
					    '-default' => $tmpdir),
                                Option->new('-name' => 'otherBackupSeries',
					    '-cf_key' => 'otherBackupSeries',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'lockFile',
					    '-cl_option' => '-L',
					    '-cl_alias' => '--lockFile',
					    '-cf_key' => 'lockFile',
					    '-default' => $lockFile),
				Option->new('-name' => 'unlockBeforeDel',
					    '-cl_option' => '--unlockBeforeDel',
					    '-cf_key' => 'unlockBeforeDel',
					    '-param' => 'yes',
					    '-only_if' => '[lockFile]'
					    ),
				Option->new('-name' => 'exceptDirs',
					    '-cl_option' => '-e',
					    '-cl_alias' => '--exceptDirs',
					    '-cf_key' => 'exceptDirs',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'includeDirs',
					    '-cl_option' => '-i',
					    '-cl_alias' => '--includeDirs',
					    '-cf_key' => 'includeDirs',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'exceptRule',
					    '-cl_option' => '--exceptRule',
					    '-cf_key' => 'exceptRule',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'includeRule',
					    '-cl_option' => '--includeRule',
					    '-cf_key' => 'includeRule',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'writeExcludeLog',
					    '-cl_option' => '--writeExcludeLog',
					    '-cf_key' => 'writeExcludeLog',
					    '-cf_noOptSet' => ['yes', 'no']),
			        Option->new('-name' => 'contExceptDirsErr',
					    '-cl_option' => '--contExceptDirsErr',
					    '-cf_key' => 'contExceptDirsErr',
					    '-cf_noOptSet' => ['yes', 'no']),
			        Option->new('-name' => 'exceptTypes',
					    '-cl_option' => '--exceptTypes',
					    '-cf_key' => 'exceptTypes',
					    '-param' => 'yes',
					    '-pattern' => '\A[Sbcfpl]+\Z'),
			        Option->new('-name' => 'archiveTypes',
					    '-cl_option' => '--archiveTypes',
					    '-cf_key' => 'archiveTypes',
					    '-param' => 'yes',
					    '-pattern' => '\A[Sbcpl]+\Z',
					    '-only_if' => '[specialTypeArchiver]'),
			        Option->new('-name' => 'specialTypeArchiver',
					    '-cl_option' => '--specialTypeArchiver',
					    '-cf_key' => 'specialTypeArchiver',
					    '-default' => 'cpio',
					    '-pattern' => '\Acpio\Z|\Atar\Z'),
				Option->new('-name' => 'cpIsGnu',
					    '-cl_option' => '--cpIsGnu',
					    '-cf_key' => 'cpIsGnu',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'linkSymlinks',
					    '-cl_option' => '--linkSymlinks',
					    '-cf_key' => 'linkSymlinks',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'precommand',
					    '-cl_option' => '--precommand',
					    '-cf_key' => 'precommand',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'postcommand',
					    '-cl_option' => '--postcommand',
					    '-cf_key' => 'postcommand',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'followLinks',
					    '-cl_option' => '--followLinks',
					    '-cf_key' => 'followLinks',
					    '-default' => 0,
					    '-pattern' => '\A\d+\Z'),
				Option->new('-name' => 'stayInFileSystem',
					    '-cl_option' => '--stayInFileSystem',
					    '-cf_key' => 'stayInFileSystem',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'highLatency',
					    '-cl_option' => '--highLatency',
					    '-cf_key' => 'highLatency',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'ignorePerms',
					    '-cl_option' => '--ignorePerms',
					    '-cf_key' => 'ignorePerms',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'lateLinks',
					    '-cl_option' => '--lateLinks',
					    '-cf_key' => 'lateLinks',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'lateCompress',
					    '-cl_option' => '--lateCompress',
					    '-only_if' => '[lateLinks]',
					    '-cf_key' => 'lateCompress',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'autorepair',
					    '-cl_option' => '--autorepair',
					    '-cf_key' => 'autorepair',
					    '-cl_alias' => '-a',
					    '-cf_noOptSet' => ['yes', 'no']),
				@blockRulesOpts,
				@blockDevicesOpts,
				Option->new('-name' => 'checkBlocksSuffix',
					    '-cl_option' => '--checkBlocksSuffix',
					    '-cf_key' => 'checkBlocksSuffix',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'checkBlocksMinSize',
					    '-cl_option' => '--checkBlocksMinSize',
					    '-cf_key' => 'checkBlocksMinSize',
					    '-default' => '100M'),
				Option->new('-name' => 'checkBlocksBS',
					    '-cl_option' => '--checkBlocksBS',
					    '-cf_key' => 'checkBlocksBS',
					    '-default' => $checkBlocksBSdefault),
				Option->new('-name' => 'checkBlocksCompr',
					    '-cl_option' => '--checkBlocksCompr',
					    '-cf_key' => 'checkBlocksCompr',
					    '-default' => 'no',
					    '-pattern' => '\Acheck\Z|\Ayes\Z|\Ano\Z'),
				Option->new('-name' => "checkBlocksParallel",
					    '-cl_option' => "--checkBlocksParallel",
					    '-cf_key' => "checkBlocksParallel",
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'queueBlock',
					    '-cl_option' => '--queueBlock',
					    '-cf_key' => 'queueBlock',
					    '-default' => $queueBlock,
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'saveRAM',
					    '-cl_option' => '--saveRAM',
					    '-cf_key' => 'saveRAM',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'compress',
					    '-cl_option' => '-c',
					    '-cl_alias' => '--compress',
					    '-cf_key' => 'compress',
					    '-quoteEval' => 'yes',
					    '-default' => \@compress),
				Option->new('-name' => 'uncompress',
					    '-cl_option' => '-u',
					    '-cl_alias' => '--uncompress',
					    '-cf_key' => 'uncompress',
					    '-quoteEval' => 'yes',
					    '-default' => \@uncompress),
				Option->new('-name' => 'postfix',
					    '-cl_option' => '-p',
					    '-cl_alias' => '--postfix',
					    '-cf_key' => 'postfix',
					    '-default' => $postfix),
#				@compressRules,
				Option->new('-name' => 'minCompressSize',
					    '-cl_option' => '--minCompressSize',
					    '-cf_key' => 'minCompressSize',
					    '-default' => $minCompressSize,
					    '-pattern' => '\A\d+\Z'),
				Option->new('-name' => 'comprRule',
					    '-cl_option' => '--comprRule',
					    '-cf_key' => 'comprRule',
					    '-quoteEval' => 'yes'),
				Option->new('-name' => 'noCompress',
					    '-cl_option' => '--noCompress',
					    '-cf_key' => 'noCompress',
					    '-param' => 'yes',
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'queueCompress',
					    '-cl_option' => '--queueCompress',
					    '-cf_key' => 'queueCompress',
					    '-default' => $queueCompress,
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'noCopy',
					    '-cl_option' => '--noCopy',
					    '-cf_key' => 'noCopy',
					    '-default' => $noCopy,
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'queueCopy',
					    '-cl_option' => '--queueCopy',
					    '-cf_key' => 'queueCopy',
					    '-default' => $queueCopy,
					    '-pattern' => '\A[1-9]\d*\Z'),
				Option->new('-name' => 'copyBWLimit',
					    '-cl_option' => '--copyBWLimit',
					    '-cf_key' => 'copyBWLimit',
					    '-param' => 'yes',
					    '-pattern' => '\A\d+\Z'),
				Option->new('-name' => 'withUserGroupStat',
					    '-cl_option' => '--withUserGroupStat',
					    '-cf_key' => 'withUserGroupStat',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'userGroupStatFile',
					    '-cl_option' => '--userGroupStatFile',
					    '-cf_key' => 'userGroupStatFile',
					    '-param' => 'yes'),
				Option->new('-name' => 'exceptSuffix',
					    '-cl_option' => '--exceptSuffix',
					    '-cf_key' => 'exceptSuffix',
					    '-multiple' => 'yes',
					    '-default' => \@exceptSuffix),
				Option->new('-name' => 'compressSuffix',
					    '-cl_option' => '--compressSuffix',
					    '-cf_key' => 'compressSuffix',
					    '-multiple' => 'yes',
					    '-default' => []),
				Option->new('-name' => 'addExceptSuffix',
					    '-cl_option' => '--addExceptSuffix',
					    '-cf_key' => 'addExceptSuffix',
					    '-multiple' => 'yes'),
				Option->new('-name' => 'doNotCompressMD5File',
					    '-cl_option' => '--doNotCompressMD5File',
					    '-cf_key' => 'doNotCompressMD5File',
					    '-cf_noOptSet' => ['yes', 'no']),
                                Option->new('-name' => 'chmodMD5File',
					    '-cl_option' => '--chmodMD5File',
					    '-cf_key' => 'chmodMD5File',
					    '-default' => $chmodMD5File,
					    '-pattern' => '\A0[0-7]{3,4}\Z'),
				Option->new('-name' => 'verbose',
					    '-cl_option' => '-v',
					    '-cl_alias' => '--verbose',
					    '-cf_key' => 'verbose',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'debug',
					    '-cl_option' => '-d',
					    '-cl_alias' => '--debug',
					    '-cf_key' => 'debug',
					    '-default' => 0,
					    '-pattern' => '\A[0-4]\Z'),
				Option->new('-name' => 'resetAtime',
					    '-cl_option' => '--resetAtime',
					    '-cf_key' => 'resetAtime',
					    '-cf_noOptSet' => ['yes', 'no']),
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
                                Option->new('-name' => 'ignoreReadError',
					    '-cl_option' => '--ignoreReadError',
					    '-cf_key' => 'ignoreReadError',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'suppressWarning',
					    '-cl_option' => '--suppressWarning',
					    '-cf_key' => 'suppressWarning',
					    '-multiple' => 'yes',
					    '-pattern' =>
  '\AexcDir\Z|\AfileChange\Z|\AcrSeries\Z|\AhashCollision\Z|\AfileNameWithLineFeed|\Ause_DB_File\Z|\Ause_MLDBM\Z|\Ause_IOCompressBzip2\Z|\AnoBackupForPeriod\Z'),
				Option->new('-name' => 'linkToRecent',
					    '-cl_option' => '--linkToRecent',
					    '-cf_key' => 'linkToRecent',
					    '-param' => 'yes'),
				Option->new('-name' => 'logFile',
					    '-cl_option' => '-l',
					    '-cl_alias' => '--logFile',
					    '-cf_key' => 'logFile',
					    '-param' => 'yes'),
				Option->new('-name' => 'plusLogStdout',
					    '-cl_option' => '--plusLogStdout',
					    '-cf_key' => 'plusLogStdout',
					    '-only_if' => '[logFile]',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'suppressTime',
					    '-cl_option' => '--suppressTime',
					    '-cf_key' => 'suppressTime',
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
					    '-default' => 'bzip2',
					    '-quoteEval' => 'yes',
					    '-only_if' =>"[logFile]"),
				Option->new('-name' => 'logInBackupDir',
					    '-cl_option' => '--logInBackupDir',
					    '-cf_key' => 'logInBackupDir',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'compressLogInBackupDir',
					    '-cl_option' =>
					    '--compressLogInBackupDir',
					    '-cf_key' => 'compressLogInBackupDir',
					    '-cf_noOptSet' => ['yes', 'no'],
					    '-only_if' => '[logInBackupDir]'),
                                Option->new('-name' => 'logInBackupDirFileName',
					    '-cl_option' =>
					    '--logInBackupDirFileName',
					    '-cf_key' => 'logInBackupDirFileName',
					    '-default' =>
					    $logInBackupDirFileName,
					    '-only_if' => '[logInBackupDir]'),
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
# hidden options
				Option->new('-name' => 'mergeBackupDir',
					    '-cf_key' => 'mergeBackupDir',
					    '-param' => 'yes'),
				Option->new('-name' => 'printAll',
					    '-cl_option' => '--printAll',
					    '-hidden' => 'yes'),
				Option->new('-name' => 'minBlockLength',
					    '-cl_option' => '--minBlockLength',
					    '-cf_key' => 'minBlockLength',
					    '-hidden' => 'yes',
					    '-default' => $checkBlocksBSmin,
					    '-pattern' => '\A\d+\Z'),
				Option->new('-name' => 'todayOpt',
					    '-cl_option' => '--today',
					    '-cf_key' => 'today',
					    '-hidden' => 'yes',
					    '-param' => 'yes'),

# ignore specified time when compairing files; possible
# values are: 'ctime', 'mtime' or 'none', default is 'none'
# Setting this parameter only makes sense in mixed
# environments, when one time has stochastic values.
                                Option->new('-name' => 'ignoreTime',
					    '-cl_option' => '--ignoreTime',
					    '-cf_key' => 'ignoreTime',
					    '-default' => 'none',
					    '-pattern' =>
					    '\Anone\Z|\Actime\Z|\Amtime\Z'),
				Option->new('-name' => 'stopAfterNoReadErrors',
					    '-cl_option' =>
					    '--stopAfterNoReadErrors',
					    '-cf_key' =>
					    'stopAfterNoReadErrors',
					    '-hidden' => 'yes',
					    '-default' => 500),
# used by storeBackupMount.pl
				Option->new('-name' => 'writeToNamedPipe',
					    '-cl_option' => '--writeToNamedPipe',
					    '-param' => 'yes',
					    '-hidden' => 'yes'),
				Option->new('-name' => 'skipSync',
					    '-hidden' => 'yes',
					    '-cl_option' => '--skipSync')
				]
		    );


$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

# Auswertung der Parameter
my $help = $CheckPar->getOptWithoutPar('help');

die "$FullHelp" if $help;

my $configFile = $CheckPar->getOptWithPar('configFile');
my $generateConfigFile = $CheckPar->getOptWithPar('generate');
my $print = $CheckPar->getOptWithoutPar('print');

my $backupDir = $CheckPar->getOptWithPar('backupDir');
my $sourceDir = $CheckPar->getOptWithPar('sourceDir');
my $series = $CheckPar->getOptWithPar('series');
my $checkCompr = $CheckPar->getOptWithoutPar('checkCompr');
$tmpdir = $CheckPar->getOptWithPar('tmpdir');
$lockFile = $CheckPar->getOptWithPar('lockFile');
my $unlockBeforeDel = $CheckPar->getOptWithPar('unlockBeforeDel');
my $exceptDirs = $CheckPar->getOptWithPar('exceptDirs');
my $includeDirs = $CheckPar->getOptWithPar('includeDirs');
my $exceptRule = $CheckPar->getOptWithPar('exceptRule');
my $includeRule = $CheckPar->getOptWithPar('includeRule');
my $writeExcludeLog = $CheckPar->getOptWithoutPar('writeExcludeLog');
my $contExceptDirsErr = $CheckPar->getOptWithoutPar('contExceptDirsErr');
my $exceptTypes = $CheckPar->getOptWithPar('exceptTypes');
$exceptTypes = '' unless $exceptTypes;
my $archiveTypes = $CheckPar->getOptWithPar('archiveTypes');
my $specialTypeArchiver = $CheckPar->getOptWithPar('specialTypeArchiver');
my $gnucp = $CheckPar->getOptWithoutPar('cpIsGnu');
my $linkSymlinks = $CheckPar->getOptWithoutPar('linkSymlinks');
my $precommand = $CheckPar->getOptWithPar('precommand');
my $postcommand = $CheckPar->getOptWithPar('postcommand');
my $followLinks = $CheckPar->getOptWithPar('followLinks');
my $stayInFileSystem = $CheckPar->getOptWithoutPar('stayInFileSystem');
my $highLatency = $CheckPar->getOptWithoutPar('highLatency');
$main::minCopyWithFork = 0 if $highLatency;
my $ignorePerms = $CheckPar->getOptWithoutPar('ignorePerms');
my $preservePerms = not $ignorePerms;
my $lateLinks = $CheckPar->getOptWithoutPar('lateLinks');
my $lateCompress = $CheckPar->getOptWithoutPar('lateCompress');
my $autorepair = $CheckPar->getOptWithoutPar('autorepair');
my $checkBlocksSuffix = $CheckPar->getOptWithPar("checkBlocksSuffix");
my $checkBlocksSuffixMinSize = $CheckPar->getOptWithPar("checkBlocksMinSize");
my $checkBlocksSuffixBS = $CheckPar->getOptWithPar("checkBlocksBS");
my $checkBlocksCompr = $CheckPar->getOptWithPar("checkBlocksCompr");
my $checkBlocksParallel = $CheckPar->getOptWithoutPar("checkBlocksParallel");
my (@checkBlocksRule, @checkBlocksBS, @checkBlocksCompr, @checkBlocksRead,
    @checkBlocksParallel);
{
    my $i;
    foreach $i (0..$noBlockRules-1)
    {
	push @checkBlocksRule, $CheckPar->getOptWithPar("checkBlocksRule$i");
	push @checkBlocksBS, $CheckPar->getOptWithPar("checkBlocksBS$i");
	push @checkBlocksCompr,
	$CheckPar->getOptWithPar("checkBlocksCompr$i");
	push @checkBlocksRead, $CheckPar->getOptWithPar("checkBlocksRead$i");
	push @checkBlocksParallel,
	$CheckPar->getOptWithoutPar("checkBlocksParallel$i");
    }
}
my (@checkDevices, @checkDevicesDir, @checkDevicesBS, @checkDevicesCompr,
    @checkDevicesParallel);
{
    my $i;
    foreach $i (0..$main::noBlockDevices-1)
    {
	push @checkDevices, $CheckPar->getOptWithPar("checkDevices$i");
	push @checkDevicesDir, $CheckPar->getOptWithPar("checkDevicesDir$i");
	push @checkDevicesBS, $CheckPar->getOptWithPar("checkDevicesBS$i");
	push @checkDevicesCompr,
	$CheckPar->getOptWithPar("checkDevicesCompr$i");
	push @checkDevicesParallel,
	$CheckPar->getOptWithoutPar("checkDevicesParallel$i");
    }
}
$queueBlock = $CheckPar->getOptWithPar('queueBlock');
my $saveRAM = $CheckPar->getOptWithoutPar('saveRAM');
my $compress = $CheckPar->getOptWithPar('compress');
my $uncompress = $CheckPar->getOptWithPar('uncompress');
$postfix = $CheckPar->getOptWithPar('postfix');
my $noCompress = $CheckPar->getOptWithPar('noCompress');
$queueCompress = $CheckPar->getOptWithPar('queueCompress');
$noCopy = $CheckPar->getOptWithPar('noCopy');
$queueCopy = $CheckPar->getOptWithPar('queueCopy');
my $copyBWLimit = $CheckPar->getOptWithPar('copyBWLimit');
my $withUserGroupStat = $CheckPar->getOptWithoutPar('withUserGroupStat');
my $userGroupStatFile = $CheckPar->getOptWithPar('userGroupStatFile');
my $exceptSuffix = $CheckPar->getOptWithPar('exceptSuffix');
my $compressSuffix = $CheckPar->getOptWithPar('compressSuffix');
my $addExceptSuffix = $CheckPar->getOptWithPar('addExceptSuffix');
$minCompressSize = $CheckPar->getOptWithPar('minCompressSize');
my $comprRule = $CheckPar->getOptWithPar('comprRule');
my $compressMD5File = $CheckPar->getOptWithoutPar('doNotCompressMD5File')
    ? 'no' : 'yes';
$chmodMD5File = $CheckPar->getOptWithPar('chmodMD5File');
my $verbose = $CheckPar->getOptWithoutPar('verbose');
my $debug = $CheckPar->getOptWithPar('debug');
my $resetAtime = $CheckPar->getOptWithoutPar('resetAtime');
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
my $ignoreReadError = $CheckPar->getOptWithoutPar('ignoreReadError');
my $suppressWarning = $CheckPar->getOptWithPar('suppressWarning');
my $linkToRecent = $CheckPar->getOptWithPar('linkToRecent');
my $logFile = $CheckPar->getOptWithPar('logFile');
my $plusLogStdout = $CheckPar->getOptWithoutPar('plusLogStdout');
my $withTime = not $CheckPar->getOptWithoutPar('suppressTime');
$withTime = $withTime ? 'yes' : 'no';
my $maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
my $noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
my $saveLogs = $CheckPar->getOptWithoutPar('saveLogs') ? 'yes' : 'no';
my $compressWith = $CheckPar->getOptWithPar('compressWith');
my $logInBackupDir = $CheckPar->getOptWithoutPar('logInBackupDir');
my $compressLogInBackupDir =
 $CheckPar->getOptWithoutPar('compressLogInBackupDir');
$logInBackupDirFileName =
 $CheckPar->getOptWithPar('logInBackupDirFileName');
my $progressReport = $CheckPar->getOptWithPar('progressReport');
my $printDepth = $CheckPar->getOptWithoutPar('printDepth');
$printDepth = $printDepth ? 'yes' : 'no';
my (@otherBackupSeries) = $CheckPar->getListPar();
# hidden options
my $printAll = $CheckPar->getOptWithoutPar('printAll');
$print = 1 if $printAll;
my $minBlockLength = $CheckPar->getOptWithPar('minBlockLength');
my $todayOpt = $CheckPar->getOptWithPar('todayOpt');  # format like
                                                      # backup dir name
my $ignoreTime = $CheckPar->getOptWithPar('ignoreTime');
my $stopAfterNoReadErrors =
    $CheckPar->getOptWithPar('stopAfterNoReadErrors');
my $writeToNamedPipe = $CheckPar->getOptWithPar('writeToNamedPipe');
my $skipSync = $CheckPar->getOptWithoutPar('skipSync');

unless ($noCompress)
{
    local *FILE;
    if (open(FILE, "/proc/cpuinfo"))
    {
	my $l;
	$noCompress = 1;
	while ($l = <FILE>)
	{
	    $noCompress++ if $l =~ /processor/;
	}
	close(FILE);
    }
    $noCompress = 2 if $noCompress < 2;
}

(@exceptSuffix) = ();
push @exceptSuffix, (@$exceptSuffix) if defined $exceptSuffix;
push @exceptSuffix, (@$addExceptSuffix) if defined $addExceptSuffix;


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
    exit 0;
}

$chmodMD5File = oct $chmodMD5File;

my (@par);
if ($logFile)
{
    push @par, ('-file' => $logFile);
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
		   'E:ERROR',
		   'P:PROGRESS',
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
$prLog1->setStopAtNoMessages('-kind' => 'E',
			     '-stopAt' => $stopAfterNoReadErrors);

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

$main::__prLog = $prLog;   # used in rules
$prLog->fork($req);


(@main::cleanup) = ($prLog, 1);

my (%suppressWarning);
{
    my $s;
    foreach $s (@$suppressWarning)
    {
	$suppressWarning{$s} = 1;
    }
}

$prLog->print('-kind' => 'E',
	      '-str' => ["missing params backupDir, sourceDir, series\n$Help"],
	      '-exit' => 1)
    unless defined $backupDir and defined $sourceDir and defined $series;


$prLog->print('-kind' => 'E',
	      '-str' => ["backupDir directory <$backupDir> does not exist\n$Help"],
	      '-exit' => 1)
    unless -e $backupDir;

$prLog->print('-kind' => 'E',
	      '-str' => ["backupDir must be the top level directory for all your",
	      "storeBackup backups on that partition. You cannot use '/' for that"],
	      '-exit' => 1)
    if $backupDir eq '/';

$prLog->print('-kind' => 'E',
	      '-str' => ["source directory <$sourceDir> does not exist"],
	      '-exit' => 1)
    unless (-d $sourceDir);

my $targetDir = "$backupDir/$series";
unless (-e $targetDir)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot create directory for series <$targetDir>"],
		  '-exit' => 1)
	unless &::makeDirPathCache($targetDir, $prLog);
    $prLog->print('-kind' => 'W',
		  '-str' => ["created directory <$targetDir>"])
	unless exists $suppressWarning{'crSeries'};
}

$prLog->print('-kind' => 'E',
	      '-str' => ["cannot write to target directory <$targetDir>"],
	      '-exit' => 1)
    unless (-w $targetDir);

$targetDir = &::absolutePath($targetDir);
$sourceDir = &::absolutePath($sourceDir);
$backupDir = &::absolutePath($backupDir);

$main::sourceDir = $sourceDir;

# check consistency of options 'archiveTypes' and 'specialTypeArchiver'
if ($specialTypeArchiver and
    ($specialTypeArchiver eq 'tar' and
     $archiveTypes =~ /S/) and not
    $exceptTypes =~ /S/)
{
    $prLog->print('-kind' => 'E',
		  '-str' =>
  ["please set 'S' for exceptTypes when using tar as specialTypeArchiver"],
		  '-exit' => 1);
}

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


$main::IOCompressDirect = 0;
{
    # build a rule from option checkBlocksSuffix
    if (defined($checkBlocksSuffix))
    {
	my $bs = (&::revertHumanReadable($checkBlocksSuffixBS))[0];
	$prLog->print('-kind' => 'E',
		      '-str' => ["checkBlocksBS too small " . 
				 "($checkBlocksSuffixBS < $checkBlocksBSmin)"],
		      '-exit' => 1)
	    if $bs < $checkBlocksBSmin;
	push @checkBlocksBS, $checkBlocksSuffixBS;
	push @checkBlocksCompr, $checkBlocksCompr;
	push @checkBlocksRule,
	['$size >= &::SIZE("' . $checkBlocksSuffixMinSize . '")' , 
	 'and',
	 '$file =~ /' . join('\Z|', @$checkBlocksSuffix) . '\Z/'];
	push @checkBlocksRead, undef;
	push @checkBlocksParallel, $checkBlocksParallel;
    }

    my $i;
    foreach $i (0..@checkBlocksRule-1)
    {
	next unless defined $checkBlocksRule[$i];

	unless (defined $checkBlocksBS[$i])
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["block size for option checkBlocksRule$i is missing"],
			  '-exit' => 1);
	}
	$flagBlockDevice = 1;
	my $bs;
	$bs = $checkBlocksBS[$i] =
	    (&::revertHumanReadable($checkBlocksBS[$i]))[0];

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["checkBlocksBS$i too small ($bs < $checkBlocksBSmin)"],
		      '-exit' => 1)
	    if $bs < $checkBlocksBSmin;

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["block size for checkBlocksRule$i is " . $checkBlocksBS[$i] .
		       ", must be $minBlockLength or more"],
		      '-exit' => 1)
	    if $bs < $minBlockLength;

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["parameter <$bs> for option checkBlocksBS%i has wrong format"],
		      '-exit' => 1)
	    unless defined $bs;
    }

    my (@chkDevices, @chkDevicesDir, @chkDevicesBS, @chkDevicesCompr,
	@chkDevicesParallel);
    foreach $i (0..@checkDevices-1)
    {
	next unless $checkDevices[$i];

	unless (defined $checkDevicesBS[$i])
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["block size for option checkDevices$i is missing"],
			  '-exit' => 1);
	}
	$flagBlockDevice = 1;
	my $bs;
	$bs = $checkDevicesBS[$i] =
	    (&::revertHumanReadable($checkDevicesBS[$i]))[0];

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["checkDevicesBS$i too small ($bs < $checkBlocksBSmin)"],
		      '-exit' => 1)
	    if $bs < $checkBlocksBSmin;

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["block size for checkDevices$i is " . $checkDevicesBS[$i] .
		       ", must be $minBlockLength or more"],
		      '-exit' => 1)
	    if $bs < $minBlockLength;

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["parameter <$bs> for option checkDevicesBS%i has wrong format"],
		      '-exit' => 1)
	    unless defined $bs;

	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["option checkDevicesDir$i not set"],
		      '-exit' => 1)
	    unless defined $checkDevicesDir[$i];

	my $devList = $checkDevices[$i];
	my $devDir = $checkDevicesDir[$i];
	my $lastDevDir = $checkDevicesDir[$i][0];
	my $j;
	foreach $j (0..@$devList-1)
	{
	    my $dev = $$devList[$j];
	    push @chkDevices, $dev;
	    $lastDevDir =  $$devDir[$j] if @$devDir - 1 >= $j;
	    push @chkDevicesDir, $lastDevDir;
	    push @chkDevicesBS, $bs;
	    push @chkDevicesCompr, $checkDevicesCompr[$i];
	    push @chkDevicesParallel, $checkDevicesParallel[$i];
	}
    }
    (@checkDevices) = (@chkDevices);    # here we have only used entries
    (@checkDevicesDir) = (@chkDevicesDir);
    (@checkDevicesBS) = (@chkDevicesBS);
    (@checkDevicesCompr) = (@chkDevicesCompr);
    (@checkDevicesParallel) = (@chkDevicesParallel);

    if ((@checkBlocksRule or @checkDevices) and
	$compress[0] eq 'bzip2')
    {
	eval "use IO::Compress::Bzip2 qw(bzip2)";
	if ($@)
	{
	    $prLog->print('-kind' => 'W',
			  '-str' =>
			  ["please install IO::Compress::Bzip2 from " .
			   "CPAN for better performance"])
		unless $suppressWarning{'use_IOCompressBzip2'};
	}
	else
	{
	    $main::IOCompressDirect = 1;
	}
    }
}

$prLog->print('-kind' => 'A',
	      '-str' => ["backing up directory <$sourceDir> to <$targetDir>"]);
$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackup.pl, $main::STOREBACKUPVERSION"]);

$prLog->print('-kind' => 'W',
	      '-str' => ["option \"copyBWLimit\" is deprecated, please " .
			 "remove from your configuration"])
    if defined $copyBWLimit;

eval "use DB_File";
if ($@)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["please install DB_File from " .
			     "CPAN for better performance"])
	unless exists $suppressWarning{'use_DB_File'};
}

# OS-Typ feststellen, um ARG_MAX zu setzen
# Default wird vorsichtshalber auf 4 KB gesetzt!
{
    my $uname = forkProc->new('-exec' => 'uname',
			      '-outRandom' => "$tmpdir/uname-",
			      '-prLog' => $prLog);
    $uname->wait();
    my $out = $uname->getSTDOUT();
    my $os = '';

    if (exists $execParamLength{$$out[0]})
    {
	$main::execParamLength = $execParamLength{$$out[0]};
	$os = ' (' . $$out[0] . ')';

	if ($$out[0] eq 'Linux' and not $gnucp)
	{
	    $gnucp = 1;
	    $prLog->print('-kind' => 'I',
			  '-str' =>
			  ["setting option 'cpIsGnu' because Linux system is recognized"]);
	}
    }
    $prLog->print('-kind' => 'I',
		  '-str' => ['setting ARG_MAX to ' . $main::execParamLength .
			     $os]);
    $out = $uname->getSTDERR();
    $prLog->print('-kind' => 'E',
		  '-str' => ["STDERR of <uname>:", @$out])
	if (@$out > 0);

    # check if external programs exist in path
    my (@missing) =
	&::checkProgExists($prLog, 'md5sum', 'cp', 'bzip2', 'mknod',
			   'mount', $compress[0], $uncompress[0]);
    if (@missing)
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["the following programs are not in \$PATH:",
				 "\t@missing",
				 "please install or check \$PATH",
				 "\$PATH is " . $ENV{'PATH'}],
		      '-exit' => 1);
    }
}


$prLog->print('-kind' => 'I',
	      '-str' => ["preserve Perms is not set"])
    if $preservePerms eq 'no';

#
# initialise include, exclude and checkBlocks rules
#
my $excRule = evalInodeRule->new('-line' => $exceptRule,
				 '-keyName' => 'exceptRule',
				 '-debug' => $debug,
				 '-tmpdir' => $tmpdir,
				 '-prLog' => $prLog);
my $incRule = evalInodeRule->new('-line' => $includeRule,
				 '-keyName' => 'includeRule',
				 '-debug' => $debug,
				 '-tmpdir' => $tmpdir,
				 '-prLog' => $prLog);

if ($checkCompr)
{
    $comprRule = evalInodeRule->new('-line' =>
	       ['$size > 1024', 'and', '&::COMPRESSION_CHECK($file)'],
				    '-keyName' => 'comprRule',
				    '-debug' => $debug,
				    '-tmpdir' => $tmpdir,
				    '-prLog' => $prLog);
}
elsif ($comprRule)
{
    $comprRule = evalInodeRule->new('-line' => $comprRule,
				    '-keyName' => 'comprRule',
				    '-debug' => $debug,
				    '-tmpdir' => $tmpdir,
				    '-prLog' => $prLog);  
}
else
{
    my (@r) = ();

    push @r, "\$size > $minCompressSize and" if $minCompressSize > 0;

    my $exceptSuffixPattern =
	join('\Z|', @exceptSuffix) . '\Z';

    push @r, "not \$file =~ /$exceptSuffixPattern/i" if @exceptSuffix;

    if ($compressSuffix)
    {
	push @r, 'and', '(';

	my $comprSuffixPattern =
	    join('\Z|', @$compressSuffix) . '\Z';
	push @r, "\$file =~ /$comprSuffixPattern/i";
	push @r, 'or';

	push @r, '&::COMPRESSION_CHECK($file)';

	push @r, ')';
    }

    $comprRule = evalInodeRule->new('-line' => \@r,
				    '-keyName' => 'comprRule',
				    '-debug' => $debug,
				    '-tmpdir' => $tmpdir,
				    '-prLog' => $prLog);
}
$prLog->print('-kind' => 'I',
	      '-str' => ["comprRule = " .
			 $comprRule->getLineString()])
    if $comprRule->hasLine();
my $chbRule = evalInodeRuleMultiple->new('-lines' => \@checkBlocksRule,
					 '-blockSize' => \@checkBlocksBS,
					 '-blockCompress' => \@checkBlocksCompr,
					 '-blockRead' => \@checkBlocksRead,
					 '-blockParallel' =>
					 \@checkBlocksParallel,
					 '-keyName' => 'checkBlocksRule',
					 '-debug' => $debug,
					 '-tmpdir' => $tmpdir,
					 '-prLog' => $prLog);


my $startDate = dateTools->new();

#
# otherBackupSeries ermitteln und in korrekter Reihenfolge sortieren
# (neueste zuletzt). Das ist wichtig, damit ctime etc. einer zu
# sichernden Datei auch den neuesten archivierten Daten verglichen
# wird.
#

# consider last of backup of all series if not specified
#print "1 otherBackupSeries = \n\t<", join(">\n\t<", @otherBackupSeries), ">\n";
if (@otherBackupSeries == 0)
{
    foreach my $d (&::readAllBackupSeries($backupDir, $prLog))
    {
	push @otherBackupSeries, "0:$d";
    }
}
else   # evaluate / replace wildcards for otherBackupSeries
{
    my (@newBackupSeries) = ();
    my (@subtractBackupSeries) = ();
    foreach my $d (@otherBackupSeries)
    {
	my ($range, $s);
	my $n = ($range, $s) = $d =~ /\A(.*?):(.*)\Z/;
	$prLog->print('-kind' => 'E',
		      '-str' => ["invalid or no range in param <$d>, exiting"],
		      '-exit' => 1)
	    unless $n == 2;

	if ($range =~ /\A\-(.*)/)        # subtract
	{
	    my (@sbs) = &evalExceptionList([$s], $backupDir, 'otherBackupSeries',
					   'avoid series', 1, undef, 1, $prLog);
	    foreach my $new (@sbs)
	    {
		push @subtractBackupSeries, "$range:$new";
	    }
	}
	else
	{
	    my (@nbs) = &evalExceptionList([$s], $backupDir, 'otherBackupSeries',
					   'consider series', 0, undef, 1, $prLog);
	    foreach my $new (@nbs)
	    {
		push @newBackupSeries, "$range:$new";
	    }
	}
    }
    # subtract @subtractBackupSeries from @newBackupSeries
    my (%newBackupSeries);
    foreach my $n (@newBackupSeries)
    {
	$n =~ /\A(.*?):(.*)\Z/;
	$newBackupSeries{$2} = $1;
    }
    foreach my $s (@subtractBackupSeries)
    {
	$s =~ /\A(.*?):(.*)\Z/;
	delete $newBackupSeries{$2} if defined $newBackupSeries{$2};
    }

    (@otherBackupSeries) = ();
    my (@pr);
    foreach my $n (sort keys %newBackupSeries)
    {
	my $r = $newBackupSeries{$n};
	$r = $1 if $r =~ /\A\+(.*)\Z/;
	push @otherBackupSeries, "$r:$n";
	push @pr, "    series <$n>";
    }
    if (@pr)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["resulting series to hard link", @pr]);
    }
    else
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["no series specified to hard link"]);
    }
}
#print "2 otherBackupSeries = \n\t<", join(">\n\t<", @otherBackupSeries), ">\n";

my $prevBackupOwnSeries = undef;
if (@otherBackupSeries > 0)
{
    push @otherBackupSeries, "0:$targetDir";
    my (@obd, $d);

    # Verzeichnisse ermitteln
    foreach $d (@otherBackupSeries)
    {
	if ($d =~ /\A(all|\d+|\d+-\d+):(.*)/)
	{
	    my $dir = $2;
            my $what = $1;
	    $dir = "$backupDir/$dir" unless $dir =~ /\A\//;
	    my $asbd =
		allStoreBackupSeries->new('-rootDir' => $dir,
					  '-checkSumFile' => $checkSumFile,
					  '-prLog' => $prLog);
#					'-absPath' => 0);
            my (@d) = sort { $b cmp $a }
	    $asbd->getAllFinishedWithoutActBackupDir();
	      # filter wanted dirs and generate absolute path
            if ($what eq "all")
	    {
                foreach my $x (@d)
		{
                    push @obd, [$dir, $x];
                }
            }
            else
	    {
                my ($from, $to);
                if ($what =~ /^(\d+)$/)
		{
                    $from = $to = $1;
                }
                elsif ($what =~ /^(\d+)-(\d+)$/)
		{
                    $from = $1;
                    $to = $2;
                }
                foreach my $i ($from .. $to)
		{
                    if (exists $d[$i])
		    {
                        push @obd, [$dir, $d[$i]];
                    }
                }
            }
        }
        else
	{
            $prLog->print('-kind' => 'E',
                          '-str' =>
			  ["invalid or no range in param <$d>, exiting"],
                          '-exit' => 1);
        }
    }

    # sort newest backup first
    (@otherBackupSeries) = ();
    my (%otherBackupSeries) = ();
    foreach $d (sort { $b->[1] cmp $a->[1] } @obd)
    {
	my $bd = $d->[0] . "/" . $d->[1];
	$bd =~ s/\/+/\//g;
	if (-d $bd and not exists $otherBackupSeries{$bd})
	{
	    $otherBackupSeries{$bd} = 1;   # do not allow double entries
	    push @otherBackupSeries, $bd;
	}
    }

    # find the previous entry from the actual backup series
    # and set it to the beginning, so it will be prefered for linking
    # therefore we minimize the number of md5 sums to calculate
#print "3 otherBackupSeries = \n\t<", join(">\n\t<", @otherBackupSeries), ">\n";
    (@obd) = ();
    foreach $d (@otherBackupSeries)
    {
	$d =~ m#\A(.*)/#;
	if ($1  eq $targetDir
	    and not $prevBackupOwnSeries)
	{
	    $prevBackupOwnSeries = $d;
#print "+1+$d\n";
	}
	else
	{
#print "+2+$d\n";
	    push @obd, $d;
	}
    }
#print "+3+$prevBackupOwnSeries\n";
    # if $prevBackupOwnSeries is still undef, this means that the the
    # reference to the previous backup in the own series does not exist
    # this means, there is no previous backup.
    # (the first backups stored in @otherBackupSeries _always_ is the
    # path to the previous backup of the own series)
    (@otherBackupSeries) = ($prevBackupOwnSeries, @obd);
}
#print "4 otherBackupSeries = \n\t<", join(">\n\t<", @otherBackupSeries), ">\n";


if ($verbose and @otherBackupSeries)
{
    my (@obd) = ();
    my $o;
    foreach $o (@otherBackupSeries)
    {
	push @obd, "   $o";
    }
    $prLog->print('-kind' => 'I',
		  '-str' => ["otherBackupSeries =", @obd]);
}

#print "5 otherBackupSeries = <", join('><', @otherBackupSeries), ">\n";

my $allLinks = lateLinks->new('-dirs' => [$backupDir],
			      '-kind' => 'recursiveSearch',
			      '-verbose' => $verbose,
			      '-autorepair' => $autorepair,
			      '-prLog' => $prLog);
#print "6 otherBackupSeries = <", join('><', @otherBackupSeries), ">\n";
unless ($lateLinks)
{
    # check, if directories with lateLinks are referenced by otherBackupSeries
    my $obd;
    foreach $obd (@otherBackupSeries)
    {
#print "checking otherBackukpDirs:\n";
	$prLog->print('-kind' => 'E',
		      '-str' => ["directory <$obd> has unresolved " .
				 "links (by parm --lateLinks)",
		                 "start ::$storeBackupUpdateBackup_prg " .
				 "to set links",
		                 "or start storeBackup.pl with --lateLinks and " .
				 "resolve later"],
		      '-exit' => 1)
	    if $allLinks->checkDir($obd);
    }
}

my $aktDate = dateTools->new();
if ($todayOpt)
{
    if ($todayOpt =~ /\A(\d{4})\.(\d{2})\.(\d{2})_(\d{2}).(\d{2}).(\d{2})\Z/)
    {
	$aktDate = dateTools->new('-year' => $1,
				  '-month' => $2,
				  '-day' => $3,
				  '-hour' => $4,
				  '-min' => $5,
				  '-sec' => $6);
	$prLog->print('-kind' => 'E',
		      '-str' =>
		      ["$todayOpt (option today) is not a valid date"],
		      '-exit' => 1)
	    unless $aktDate->isValid();
	$prLog->print('-kind' => 'W',
		      '-str' => ["setting today to " .
				 $aktDate->getDateTime()]);
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["format error at option today, must be",
				 "  YYYY.MM.DD_HH.MM.SS"],
		      '-exit' => 1);
    }
}

$main::stat = Statistic->new('-startDate' =>
			     $precommand ? $startDate : undef,
			     '-aktDate' => $aktDate,
			     '-userGroupStatFile' => $userGroupStatFile,
			     '-exceptSuffix' => $exceptSuffix,
			     '-prLog' => $prLog,
			     '-progressReport' => $progressReport,
			     '-progressDeltaTime' => $progressDeltaTime,
			     '-withUserGroupStat' => $withUserGroupStat,
			     '-userGroupStatFile' => $userGroupStatFile,
			     '-compress' => $compress);


#
# check if all exceptDirs and includeDirs are relative Paths
#
{
    my $error = 0;
    my $d;
    foreach $d (@$exceptDirs)
    {
	if ($d =~ /\A\//o)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["exceptDir <$d> is not a relative path!"]);
	    $error = 1;
	}
    }
    foreach $d (@$includeDirs)
    {
	if ($d =~ /\A\//o)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["includeDir <$d> is not a relative path!"]);
	    $error = 1;
	}
    }
    $prLog->print('-kind' => 'E',
		  '-str' => ["exiting"],
		  '-exit' => 1)
	if $error;
}

#
# exception- und include- Liste überprüfen und evaluieren
# + checkBlocksRule 
#
my (@exceptDirs) = &evalExceptionList($exceptDirs, $sourceDir,
				   'exceptDir', 'excluding',
				      $contExceptDirsErr, undef, 0, $prLog);
my (@includeDirs) = &evalExceptionList($includeDirs, $sourceDir,
				    'includeDir', 'including',
				       $contExceptDirsErr, undef, 0, $prLog);
$prLog->print('-kind' => 'I',
	      '-str' => ["exceptRule = " . $excRule->getLineString()])
    if $exceptRule;
$prLog->print('-kind' => 'I',
	      '-str' => ["includeRule = " . $incRule->getLineString()])
    if $includeRule;
$prLog->print('-kind' => 'I',
	      '-str' => ["checkBlocksRule = <"
			 . $chbRule->getLineString() . ">"])
    if $chbRule->hasLine();
{
    my $i;
    foreach $i (0..@checkDevices-1)
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["saving devices <" . $checkDevices[$i] . "> -> " .
		       $checkDevicesDir[$i] . " (block size = " .
		       $checkDevicesBS[$i] . ", " .
		       'compression: ' . $checkDevicesCompr[$i] . ')']);
    }
}


#
# check if backupDir is a subdir of sourceDir
#
my $targetInSource = 0;
if (&::isSubDir($sourceDir, $targetDir))    # liegt drin!
{
    $targetInSource = 1;                 # Annahme: es gibt keine Ausnahme
    if (@exceptDirs > 0)                 # testen, ob vielleicht im vom
    {                                    # Backup ausgenommenen Tree
	my $e;
	foreach $e (@exceptDirs)
	{
	    if (&::isSubDir($e, $targetDir))
	    {
		$targetInSource = 0;     # doch Ausnahme gefunden
		$prLog->print('-kind' => 'I',
			      '-str' =>
			      ["target directory <$targetDir> is in " .
			       "exception <$e> of source directory " .
			       "<$sourceDir>, ok"]);
		last;
	    }
	}
    }
    if ($targetInSource == 1 and
	@includeDirs > 0)            # check, if not in include paths
    {
	my $i;
	my $targetInSource = 0;      # assumption: target is not in source
	foreach $i (@includeDirs)
	{
	    if (&::isSubDir($i, $targetDir))
	    {
		$targetInSource = 1;
		last;
	    }
	}
    }
}
$prLog->print('-kind' => 'E',
	      '-str' =>
	      ["backup directory <$targetDir> cannot be part of the " .
	       "source directory <$sourceDir>",
	       "define an exception with --exceptDirs or choose another " .
	       "target directory"],
	      '-exit' => 1)
    if ($targetInSource);

#
# check if all exceptDirs are subdirectories of includeDirs or
# generate a warning
# also check for same directories in includeDirs and excludeDirs
#
my $SameInclExcl = 0;
if (@exceptDirs and @includeDirs and not exists $suppressWarning{'excDir'})
{
    my $e;
    foreach $e (@exceptDirs)
    {
	my $i;
	my $isIn = 0;
	foreach $i (@includeDirs)
	{
	    if ($i eq $e)      # same directory chosen for include and exclude
	    {
		$SameInclExcl = 1;
		$prLog->print('-kind' => 'E',
			      '-str' =>
			      ["configuration error: <$i> chosen " .
			       "for options includeDirs and excludeDirs"]);
	    }
	    if (&::isSubDir($i, $e))
	    {
		$isIn = 1;
		last;
	    }
	}
	$prLog->print('-kind' => 'W',
		      '-str' => ["except dir <$e> is not part of the backup"])
	    unless $isIn;
    }
}
exit 1 if $SameInclExcl;

#
# lock file überprüfen
#
::checkLockFile($lockFile, $prLog);

# prepare exceptTypes
my (%exTypes, $et);
foreach $et (split(//, $exceptTypes || ""))
{
    $exTypes{$et} = 0;         # this is a flag and and also a counter
}

#
# precommand ausführen
#
if (defined $precommand)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["starting pre command <@$precommand> ..."]);
    my ($preComm, @preParam) = (@$precommand);
    my $preco = forkProc->new('-exec' => $preComm,
			      '-param' => \@preParam,
			      '-workingDir' => '.',
			      '-outRandom' => "$tmpdir/precomm-",
			      '-prLog' => $prLog);
    $preco->wait();
    my $out = $preco->getSTDOUT();
    $prLog->print('-kind' => 'W',
		  '-str' => ["STDOUT of <@$precommand>:", @$out])
	if (@$out > 0);
    $out = $preco->getSTDERR();
    $prLog->print('-kind' => 'E',
		  '-str' => ["STDERR of <@$precommand>:", @$out])
	if (@$out > 0);

    my $status = $preco->get('-what' => 'status');
    if ($status == 0)
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["pre command <@$precommand> finished with status 0"]);
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["pre command <@$precommand> finished with " .
				 "status $status, exiting"]);
	unlink $lockFile if $lockFile;
	exit 1;
    }
}


#
# Erzeugen der benötigten Objekte
#
my $adminDirs = adminDirectories->new('-targetDir' => $targetDir,
				      '-checkSumFile' => $checkSumFile,
				      '-tmpdir' => $tmpdir,
				      '-chmodMD5File' => $chmodMD5File,
				      '-prLog' => $prLog,
				      '-aktDate' => $aktDate,
				      '-debugMode' => $debug);

my $indexDir = indexDir->new();

my $aktFilename =
    aktFilename->new('-infoFile' => $adminDirs->getAktInfoFile(),
		     '-blockCheckSumFile' =>
		     $adminDirs->getAktDir() . "/$blockCheckSumFile",
		     '-compressMD5File' => $compressMD5File,
		     '-sourceDir' => $sourceDir,
		     '-followLinks' => $followLinks,
		     '-compress' => $compress,
		     '-uncompress' => $uncompress,
		     '-postfix' => $postfix,
		     '-comprRule' => $comprRule,
		     '-exceptRule' => $excRule,
		     '-includeRule' => $incRule,
		     '-writeExcludeLog' => $writeExcludeLog,
		     '-exceptTypes' => $exceptTypes,
		     '-specialTypeArchiver' => $specialTypeArchiver,
		     '-archiveTypes' => $archiveTypes,
		     '-checkBlocksRule' => \@checkBlocksRule,
		     '-checkBlocksBS' => \@checkBlocksBS,
		     '-checkBlocksCompr' => \@checkBlocksCompr,
		     '-checkBlocksRead' => \@checkBlocksRead,
		     '-checkDevices' => \@checkDevices,
		     '-checkDevicesDir' => \@checkDevicesDir,
		     '-checkDevicesBS' => \@checkDevicesBS,
		     '-checkDevicesCompr' => \@checkDevicesCompr,
		     '-lateLinks' => $lateLinks,
		     '-logInBackupDir' => $logInBackupDir,
		     '-compressLogInBackupDir' => $compressLogInBackupDir,
		     '-logInBackupDirFileName' => $logInBackupDirFileName,
		     '-exceptDirs' => \@exceptDirs,
		     '-includeDirs' => \@includeDirs,
		     '-aktDate' => $aktDate,
		     '-chmodMD5File' => $chmodMD5File,
		     '-indexDir' => $indexDir,
		     '-prLog' => $prLog);

my $setResetDirTimesFile = &::uniqFileName("$tmpdir/storeBackup-dirs.$$");
my $setResetDirTimes =
    setResetDirTimes->new('-tmpDir' => $tmpdir,
			  '-sourceDir' => $sourceDir,
			  '-targetDir' => $adminDirs->getAktDir(),
			  '-prLog' => $prLog,
			  '-srdtf' => $setResetDirTimesFile,
			  '-doNothing' => $lateLinks ? 1 : 0,
			  '-resetAtime' => $resetAtime,
			  '-preservePerms' => $preservePerms);

my $prLog2 = undef;
if ($logInBackupDir)      # auch in BackupDirs herinloggen
{
    $logInBackupDirFileName =
	$adminDirs->getAktDir() . "/$logInBackupDirFileName",
    $prLog2 = printLog->new('-kind' => $prLogKind,
			    '-file' => $logInBackupDirFileName,
			    '-withTime' => 'yes',
			    '-maxFilelen' => 0,
			    '-noOfOldFiles' => 1,
			    '-tmpdir' => $tmpdir);
    $prLog->add('-prLogs' => [$prLog2]);
}

my $delOld =
    deleteOldBackupDirs->new('-targetDir' => $targetDir,
			     '-doNotDelete' => $doNotDelete,
			     '-deleteNotFinishedDirs' => $deleteNotFinishedDirs,
			     '-checkSumFile' => $checkSumFile,
			     '-actBackupDir' => $adminDirs->getAktDir(),
			     '-prLog' => $prLog,
			     '-today' => $aktDate,
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
			     '-statDelOldBackupDirs' => $main::stat,
			     '-lateLinksParam' => $lateLinks,
			     '-allLinks' => $allLinks,
			     '-suppressWarning' => \%suppressWarning
			     );
$delOld->checkBackups();

my $oldFilename =
    oldFilename->new('-dbmBaseName' => "$tmpdir/dbm",
		     '-indexDir' => $indexDir,
		     '-progressReport' => $progressReport,
		     '-aktDir' => $adminDirs->getAktDir(),
		     '-otherBackupSeries' => \@otherBackupSeries,
		     '-prLog' => $prLog,
		     '-checkSumFile' => $checkSumFile,
		     '-debugMode' => $debug,
		     '-saveRAM' => $saveRAM,
		     '-flagBlockDevice' => $flagBlockDevice,
		     '-tmpdir' => $tmpdir
    );

$aktFilename->setDBMmd5($oldFilename->getDBMmd5());

$writeExcludeLog = $adminDirs->getAktDir() . "/.storeBackup.notSaved.bz2"
    if $writeExcludeLog;

my $readDirAndCheck =
    readDirCheckSizeTime->new('-adminDirs' => $adminDirs,
			      '-oldFilename' => $oldFilename,
			      '-aktFilename' => $aktFilename,
			      '-dir' => $sourceDir,
			      '-followLinks' => $followLinks,
			      '-stayInFileSystem' => $stayInFileSystem,
                              '-cpIsGnu' => ($gnucp or $specialTypeArchiver),
			      '-exceptDirs' => [@exceptDirs],
			      '-includeDirs' => [@includeDirs],
			      '-writeExcludeLog' => $writeExcludeLog,
			      '-aktDir' => $adminDirs->getAktDir(),
			      '-postfix' => $postfix,
			      '-exceptRule' => $excRule,
			      '-includeRule' => $incRule,
			      '-checkBlocksRule' => $chbRule,
			      '-exTypes' => \%exTypes,
			      '-resetAtime' => $resetAtime,
			      '-debugMode' => $debug,
			      '-verbose' => $verbose,
			      '-tmpdir' => $tmpdir,
			      '-prLog' => $prLog,
			      '-ignoreReadError' => $ignoreReadError,
			      '-ignoreTime' => $ignoreTime,
			      '-printDepth' => $printDepth);

my $parForkCopy = parallelFork->new('-maxParallel' => $noCopy,
				    '-prLog' => $prLog);
my $parForkCompr = parallelFork->new('-maxParallel' => $noCompress,
				     '-prLog' => $prLog);
my $parForkBlock = parallelFork->new('-maxParallel' => 1,
				     '-prLog' => $prLog);

# option saveRAM for rule functions main::MARK_DIR and main::MARK_DIR_REC
my $stbuEXCLfilename = undef;
my $stbuEXCLRECfilename = undef;
my $stbuINCLRECfilename = undef;
my $makeDirPathFilename = undef;
if ($saveRAM)
{
	$stbuEXCLfilename = &::uniqFileName("$tmpdir/stbuEXCL.$$.");
	%main::MARK_DIR_Cache = ();
#	tie(%main::MARK_DIR_Cache, "DB_File", $stbuEXCLfilename,
#	    O_CREAT|O_RDWR, 0600) or
	dbmopen(%main::MARK_DIR_Cache, $stbuEXCLfilename, 0600) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot write to $stbuEXCLfilename"],
			      '-exit' => 1);

	$stbuEXCLRECfilename = &::uniqFileName("$tmpdir/stbuEXCLREC.$$.");
	%main::MARK_DIR_REC_Cache = ();
#	tie(%main::MARK_DIR_REC_Cache, "DB_File", $stbuEXCLRECfilename,
#	    O_CREAT|O_RDWR, 0600) or
	dbmopen(%main::MARK_DIR_REC_Cache, $stbuEXCLRECfilename, 0600) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot write to $stbuEXCLRECfilename"],
			      '-exit' => 1);

	$stbuINCLRECfilename = &::uniqFileName("$tmpdir/stbuINCLREC.$$.");
	%main::MARK_DIR_INCL_REC_Cache = ();
#	tie(%main::MARK_DIR_INCL_REC_Cache, "DB_File", $stbuINCLRECfilename,
#	    O_CREAT|O_RDWR, 0600) or
	dbmopen(%main::MARK_DIR_INCL_REC_Cache, $stbuINCLRECfilename, 0600) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot write to $stbuINCLRECfilename"],
			      '-exit' => 1);

	$makeDirPathFilename = &::uniqFileName("$tmpdir/stbuMakeDir.$$.");
	%main::makeDirPathCache = ();
	dbmopen(%main::makeDirPathCache, $makeDirPathFilename, 0600) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot write to $makeDirPathFilename"],
			      '-exit' => 1);
}


# signal handling
(@main::cleanup) =      # Objekte verfügbar machen
    ($prLog, 0, $oldFilename, $aktFilename, $parForkCopy, $parForkCompr, $tmpdir,
     $setResetDirTimesFile, $lockFile, $stbuEXCLfilename, $stbuEXCLRECfilename,
     $makeDirPathFilename);
$SIG{INT} = \&cleanup;
$SIG{TERM} = \&cleanup;


my $fifoCopy = fifoQueue->new('-maxLength' => $queueCopy,
			      '-prLog' => $prLog);
my $fifoCompr = fifoQueue->new('-maxLength' => $queueCompress,
			       '-prLog' => $prLog);
my $fifoBlock = fifoQueue->new('-maxLength' => $queueBlock,
			       '-prLog' => $prLog);

my $scheduler =
    Scheduler->new('-aktFilename' => $aktFilename,
		   '-oldFilename' => $oldFilename,
		   '-followLinks' => $followLinks,
		   '-prevBackupOwnSeries' => $prevBackupOwnSeries,
		   '-readDirAndCheck' => $readDirAndCheck,
		   '-setResetDirTimes' => $setResetDirTimes,
		   '-parForkCopy' => $parForkCopy,
		   '-fifoCopy' => $fifoCopy,
		   '-parForkCompr' => $parForkCompr,
		   '-noCompress' => $noCompress,
		   '-blockCheckSumFile' => $blockCheckSumFile,
		   '-parForkBlock' => $parForkBlock,
		   '-fifoBlock' => $fifoBlock,
		   '-compress' => $compress,
		   '-postfix' => $postfix,
		   '-fifoCompr' => $fifoCompr,
		   '-comprRule' => $comprRule,
		   '-targetDir' => $adminDirs->getAktDir(),
		   '-aktInfoFile' => $checkSumFile,
		   '-resetAtime' => $resetAtime,
		   '-tmpdir' => $tmpdir,
		   '-prLog' => $prLog,
                   '-cpIsGnu' => $gnucp,
		   '-linkSymlinks' => $linkSymlinks,
		   '-lateLinks' => $lateLinks,
		   '-lateCompress' => $lateCompress,
		   '-suppressWarning' => \%suppressWarning,
                   '-preservePerms' => $preservePerms,
		   '-debugMode' => $debug);

$main::tinyWaitScheduler = tinyWaitScheduler->new('-firstFast' => 1,
						  '-maxWaitTime' => .2,
						  '-noOfWaitSteps' => 100,
					          '-prLog' => $prLog,
					          '-debug' => $debug);
{
    my $i;
    foreach $i (0..@checkDevices-1)
    {
	$fifoBlock->add('-value' => ['device', $checkDevices[$i],
				     $checkDevicesDir[$i], $checkDevicesBS[$i],
				     $checkDevicesCompr[$i],
				     $checkDevicesParallel[$i]]);
    }
}


$scheduler->normalOperation();   # die eigentliche Verarbeitung

$setResetDirTimes->writeTimes(); # set atime, mtime for directories

$aktFilename->closeInfoFile();
$oldFilename->readDBMFilesSize();
$oldFilename->delDBMFiles();     # dbm files löschen

if ($stbuEXCLfilename)
{
#    untie %main::MARK_DIR_Cache;
    dbmclose(%main::MARK_DIR_Cache);
    unlink $stbuEXCLfilename;
}
if ($stbuEXCLRECfilename)
{
#    untie %main::MARK_DIR_REC_Cache;
    dbmclose(%main::MARK_DIR_REC_Cache);
    unlink $stbuEXCLRECfilename;
}
if ($stbuINCLRECfilename)
{
#    untie %main::MARK_DIR_INCL_Cache;
    dbmclose(%main::MARK_DIR_INCL_Cache);
    unlink $stbuINCLRECfilename;
}
if ($makeDirPathFilename)
{
    dbmclose(%main::makeDirPathCache);
    unlink $makeDirPathFilename;
}


if ($linkToRecent)
{
    if (-l "$targetDir/$linkToRecent")
    {
	unlink "$targetDir/$linkToRecent";

	my ($_d, $link) = &::splitFileDir($adminDirs->getAktDir());
	$prLog->print('-kind' => 'W',
		      '-str' => ["cannot create symlink linkToRecent " .
				 "<$linkToRecent>"])
	    unless symlink $link, "$targetDir/$linkToRecent";
    }
    elsif (-e "$targetDir/$linkToRecent")
    {
	$prLog->print('-kind' => 'W',
		      '-str' => ["cannot delete <$linkToRecent> " .
				 "(option linkToRecent): " .
				 "is not a symbolic link"]);
    }
}


unless ($skipSync)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["syncing ..."]);
    system "/bin/sync";
}


{my $XXXXX = $main::finishedFlag;}   # to make perl happy
my $finished = $adminDirs->getAktDir() . "/$main::finishedFlag";
local *FILE;
&::checkDelSymLink("$finished", $prLog, 0x01);
open(FILE, ">", "$finished") or
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot open <$finished>"],
		  '-add' => [__FILE__, __LINE__],
		  '-exit' => 1);
FILE->autoflush(1);
close(FILE) or
    $prLog->print('-kind' => "E",
		  '-str' => ["couldn't close <$finished>: $!"]);


#
# jetzt noch alte Backups löschen
#
$delOld->deleteBackups();


#
# postcommand ausführen
#

if (defined $postcommand)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["starting post command <@$postcommand> ..."]);
    my ($postComm, @postParam) = (@$postcommand);
    my $postco = forkProc->new('-exec' => $postComm,
			      '-param' => \@postParam,
			      '-workingDir' => '.',
			      '-outRandom' => "$tmpdir/postcomm-",
			      '-prLog' => $prLog);
    $postco->wait();
    my $out = $postco->getSTDOUT();
    $prLog->print('-kind' => 'W',
		  '-str' => ["STDOUT of <@$postcommand>:", @$out])
	if (@$out > 0);
    $out = $postco->getSTDERR();
    $prLog->print('-kind' => 'E',
		  '-str' => ["STDERR of <@$postcommand>:", @$out])
	if (@$out > 0);

    my $status = $postco->get('-what' => 'status');
    if ($status == 0)
    {
	$prLog->print('-kind' => 'I',
		      '-str' =>
		      ["post command <@$postcommand> finished with status 0"]);
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["post command <@$postcommand> finished " .
				 "with status $status"]);
	unlink $lockFile if $lockFile;
	exit 1;
    }
}

# lock file löschen
if ($lockFile and $unlockBeforeDel)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["removing lock file <$lockFile>"]);
    unlink $lockFile;
    $lockFile = undef;
}


# Größe von .md5CheckSum-Datei noch für Statistik berücksichtigen
$main::stat->setSizeMD5CheckSum($adminDirs->getAktInfoFile(),
				$compressMD5File);
$main::stat->setUsedSizeQueues($fifoCopy->getMaxUsedLength(),
			       $fifoCompr->getMaxUsedLength());
$main::stat->print('-exTypes' => \%exTypes);

# lock file löschen
if ($lockFile)
{
    $prLog->print('-kind' => 'I',
		  '-str' => ["removing lock file <$lockFile>"]);
    unlink $lockFile;
}

if ($compressLogInBackupDir)             # log file im BackupDir noch
{                                        # komprimieren
    $prLog->sub('-prLogs' => [$prLog2]);
    my $compressLog = forkProc->new('-exec' => 'bzip2',
				    '-param' => [$logInBackupDirFileName],
				    '-outRandom' => "$tmpdir/comprLog-",
				    '-prLog' => $prLog);
    $compressLog->wait();
}

my $enc = $prLog->encountered('-kind' => 'W');
my $S = $enc > 1 ? 'S' : '';
$prLog->print('-kind' => 'W',
	      '-str' => ["-- $enc WARNING$S OCCURRED DURING THE BACKUP! --"])
    if $enc;

$enc = $prLog->encountered('-kind' => 'E');
$S = $enc > 1 ? 'S' : '';
$prLog->print('-kind' => 'E',
	      '-str' => ["-- $enc ERROR$S OCCURRED DURING THE BACKUP! --"])
    if $enc;


if ($prLog->encountered('-kind' => "E"))
{
    $prLog->print('-kind' => 'Z',
		  '-str' => ["backing up directory <$sourceDir> to <" .
			     $adminDirs->getAktDir() . ">"]);
    exit 1;
}
else
{
    $prLog->print('-kind' => 'Z',
		  '-str' => ["backing up directory <$sourceDir> to <" .
			     $adminDirs->getAktDir() . ">"]);
    exit 0;
}


##################################################
sub cleanup
{
    my $signame = shift;
    my $exit = (shift() || 1);

    my ($prLog, $onlyLateLinkCheck, $oldFilename, $aktFilename, $parForkCopy,
	$parForkCompr, $tmpdir, $setResetDirTimesFile, $lockFile,
	$stbuEXCLfilename, $stbuEXCLRECfilename, $makeDirPathFilename)
	= (@main::cleanup);

    unlink $lockFile if $lockFile;

    $main::endOfStoreBackup = 1;

    if ($signame)
    {
        $prLog->print('-kind' => 'E',
                      '-str' => ["caught signal $signame, terminating"]);
    }

    unless ($onlyLateLinkCheck)
    {
	# Dateien schließen, aufräumen
	$aktFilename->delInfoFile();
	$oldFilename->delDBMFiles();     # dbm files löschen
	unlink $setResetDirTimesFile;

	# laufende Prozesse abschießen
	$parForkCopy->signal('-value' => 2);
	$parForkCompr->signal('-value' => 2);

	$prLog->print('-kind' => 'Z',
		      '-str' => ["backing up directory <$sourceDir>"]);
    }

    if ($stbuEXCLfilename)
    {
#	untie %main::MARK_DIR_Cache;
	dbmclose(%main::MARK_DIR_Cache);
	unlink $stbuEXCLfilename;
    }
    if ($stbuEXCLRECfilename)
    {
#	untie %main::MARK_DIR_REC_Cache;
	dbmclose(%main::MARK_DIR_REC_Cache);
	unlink $stbuEXCLRECfilename;
    }
    if ($stbuINCLRECfilename)
    {
#	untie %main::MARK_DIR_INCL_Cache;
	dbmclose(%main::MARK_DIR_INCL_Cache);
	unlink $stbuINCLRECfilename;
    }

    if ($makeDirPathFilename)
    {
	dbmclose(%main::makeDirPathCache);
	unlink $makeDirPathFilename;
    }

    exit $exit;
}


########################################
sub calcBlockMD5Sums
{
    my $sourceDir = shift;
    my $targetDir = shift;
    my $relPath = shift;          # relative path in backup incl. file
    my $blockSize = shift;
    my $compressBlock = shift;    # 'c' oder 'u' (compress, uncompress)
    my $blockRead = shift;        # pointer to list
    my $compressCommand = shift;
    my $compressOptions = shift;
    my $postfix = shift;
    my $oldFilename = shift;      # pointer to object
    my $lateLinks = shift;
    my $lateCompress = shift;
    my $noCompress = shift;
    my $prLog = shift;
    my $tmpfile = shift;
    my $blockCheckSumFile = shift;
    my $ctime = shift;
    my $mtime = shift;

#print "calcMD5BlockSums\n";
#print "\tsourceDir = <$sourceDir>\n";
#print "\ttargetDir = <$targetDir>\n";
#print "\trelPath = <$relPath>\n";
#print "\tblockSize = <$blockSize>\n";
#print "\ttmpfile = <$tmpfile>\n";
#print "\tcompressBlock = <$compressBlock>\n";
#print "\tlateCompress = <$lateCompress>\n" if $lateCompress;

    $0 = "perlmd5block $relPath";

    my $manageNewBlock =
	manageNewBlockMD5toFilename->new('-oldFilename' => $oldFilename,
					 '-dir' => $targetDir,
					 '-relPath' => $relPath,
					 '-prLog' => $prLog);

    # explanations:
    ## $lateLinks
    ##  if defined, write lateLinks
    ## $lateCompress
    ##  from option
    ## $direct
    ##  == 0 -> fork for compression / == 1 -> compress in perl

    my $comprCheck;
    if ($compressBlock eq 'no')
    {
	$compressBlock = 'u';
	$comprCheck = undef;
    }
    elsif ($compressBlock eq 'yes')
    {
	$compressBlock = 'c';
	$comprCheck = undef;
    }
    else
    {
	$compressBlock = 'c';    # because if dependeny of lateCompress
	                         # (see below)
	$comprCheck = 1;
    }

    $lateCompress = undef if $compressBlock eq 'u';  # must not be compressed

    my ($noWarnings, $noErrors) = (0, 0);
    my ($noBlockComprCheckCompr, $noBlockComprCheckCp) = (0, 0);

    my $mkdirLateLinksFilePath = undef;
    local (*FILE, *OUT);
    my $fileIn = undef;    # used to read via pipe (filter)
    if (@$blockRead)   # $blockRead = pointer to program to pipe in block to read
    {
	my ($prog, @par) = (@$blockRead);
	my (@p);
	if ($ctime == 0)               # device
	{
	    (@p) = ('-stderr' => '/dev/null');
	}
	else    # blocked file
	{
	    (@p) = ('-outRandom' => "$tmpdir/stbuPipeFrom10-");
	}
	$fileIn = pipeFromFork->new('-exec' => $prog,
				    '-param' => \@par,
				    '-stdin' => $sourceDir,
				    @p,
				    '-prLog' => $prLog);

    }
    else
    {
	unless (sysopen(FILE, $sourceDir, O_RDONLY))
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open <$sourceDir>"],
			  '-add' => [__FILE__, __LINE__]);
	    ++$noErrors;
	    return 0;
	}
    }

    my $md5All = Digest::MD5->new();
    my $blockNo = 0;
    my $buffer;
    my (@newMD5line) = ();
    my ($statSizeOrig, $statSizeNew, $statNoForksCP, $statNoForksCompress,
	$statNoLateLinks, $n) = (0, 0, 0, 0, 0, 0);

    my $paralFork = parallelFork->new('-maxParallel' => $noCompress,
				      '-prLog' => $prLog);
    my $tinySched = tinyWaitScheduler->new('-prLog' => $prLog);

    my $direct = 0;    # == 1 -> do not fork for compression or copy
    $direct = 1 if $compressBlock eq 'u';
    $direct = 1 if $main::IOCompressDirect
	and $blockSize < $main::minCopyWithFork
	and $compressBlock eq 'c';
#print "direct = <$direct>\n";

    my $jobToDo = 1;
    my $parForkToDo = 0;

    unless (open(OUT, ">", $tmpfile))
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot open temporary file <$tmpfile>"]);
	++$noErrors;
	return 1;                         # ERROR
    }

    while ($jobToDo > 0 or $parForkToDo > 0)
    {
#print "--- jobToDo=$jobToDo -- parForkToDo=$parForkToDo ---\n";
	#############################
	my $old = $paralFork->checkOne();
	if ($old)
	{
	    my ($digest, $file, $postfix) = @{$old->get('-what' => 'info')};
	    $statSizeNew += (stat("$targetDir/$file$postfix"))[7] || 0;
#print "-1- md5 $file <$postfix>\n";
	}

	#############################
#print "jobToDo = <$jobToDo>, freeEntries = <", $paralFork->getNoFreeEntries(), ">\n";
	if ($jobToDo > 0 and $paralFork->getNoFreeEntries() > 0)
	{
	    if ($fileIn)
	    {
		$n = $fileIn->sysread(\$buffer, $blockSize);
	    }
	    else
	    {
		$n = sysread(FILE, $buffer, $blockSize);
	    }

	    if ($n)
	    {
		$statSizeOrig += $n;
		$blockNo++;
		my $blockName = sprintf "%010d", $blockNo;
		my $blockFile = "$relPath/$blockName";
		my $digest = md5_hex($buffer);
		$md5All->add($buffer);
#print "-2- $blockName -> digest = $digest ($n bytes)\n";
		my ($existingFile, $compr, $n1);
		if ($n1 = (($compr, $existingFile) =
#			   $oldFilename->getBlockFilenameCompr($digest)))
$manageNewBlock->getBlockFilename($digest)))
		{                                          # block exists
		    $blockFile .= $postfix if $compr eq 'c';

		    push @newMD5line, "$digest $compr $blockFile";
#print "-10- ($digest) link -> $existingFile -> $targetDir/$blockFile\n";
		    if ($lateLinks)
		    {
			if (not $mkdirLateLinksFilePath)
			{
			    &::makeFilePathCache("$targetDir/$blockFile", $prLog);
			    $mkdirLateLinksFilePath = 1;
			}
			print OUT "link $digest\n$existingFile\n$targetDir/$blockFile\n";
			++$statNoLateLinks;
		    }
		    else
		    {
#print "-10.2- <$existingFile>\n";
			&::waitForFile($existingFile);
			unless (link $existingFile, "$targetDir/$blockFile")
			{
#print "-10.3-\n";
			    if ($compressBlock eq 'c')
			    {
#print "A\n";
				$paralFork->add_noblock(
				    '-function' => \&compressOneBlock,
				    '-funcPar' =>
				    [$buffer,
#				     "$targetDir/$blockFile$postfix",
				     "$targetDir/$blockFile",
				     $compressCommand,
				     $compressOptions,
				     $prLog, $tmpdir],
				    '-info' => [$digest,
						"$relPath/$blockName",
#						'']);
						$postfix]);
				++$statNoForksCompress;

#				push @newMD5line,
#				"$digest $compressBlock $relPath/$blockName";
#				"$digest $compressBlock $relPath/$blockName$postfix";
#print "-10.4-\n";
			    }
			    else
			    {
#print "-10.5-\n";
				::copyOneBlock($buffer, "$targetDir/$relPath/$blockName",
					       $prLog);
				$statSizeNew += (stat("$targetDir/$relPath/$blockName"))[7] || 0;

			    }
#print "-10.6-\n";
#			    $oldFilename->setBlockFilenameCompr($digest,
#								"$targetDir/$blockFile",
$manageNewBlock->setBlockFilename($digest,
				  $blockFile,
								$compressBlock);
			}
#print "-10.7-\n";
		    }
		}
		else        # block is new
		{
#print "-11- new block\n";
		    if ($lateLinks and not $mkdirLateLinksFilePath)
		    {
			&::makeFilePathCache("$targetDir/$blockFile", $prLog);
			$mkdirLateLinksFilePath = 1;
		    }

		    if ($comprCheck)
		    {
			my $comprCheckBuffer;
			::gzip \$buffer => \$comprCheckBuffer, Level => 1;
			if (length($comprCheckBuffer)/length($buffer) < 0.95)
			{
#print "-11.5- compress_check: compress\n";
			    $compressBlock = 'c';
			    ++$noBlockComprCheckCompr;
			}
			else
			{
#print "-11.5- compress_check: copy\n";
			    $compressBlock = 'u';
			    ++$noBlockComprCheckCp;
			}
		    }

		    my $pf = $compressBlock eq 'c' ? $postfix : '';
#		    $oldFilename->setBlockFilenameCompr($digest,
#							"$targetDir/$blockFile$pf",
$manageNewBlock->setBlockFilename($digest,
				  "$blockFile$pf",
							$compressBlock);
		    if ($lateCompress and ($compressBlock eq 'c'))
		    {
#print "-12- late compress\n";
			if ($direct)
			{
			    ::copyOneBlock($buffer, "$targetDir/$relPath/$blockName",
					   $prLog);
			    $statSizeNew += (stat("$targetDir/$relPath/$blockName"))[7] || 0;
			}
			else
			{
#print "B\n";
			    $paralFork->add_noblock('-function' => \&copyOneBlock,
						    '-funcPar' => [$buffer,
						     "$targetDir/$relPath/$blockName",
								   $prLog],
						    '-info' => [$digest,
							 "$relPath/$blockName",
								'']);
			    ++$statNoForksCP;
			}
			print OUT "compress $digest\n" .
			    "$targetDir/$relPath/$blockName\n";
			push @newMD5line,
			    "$digest $compressBlock $relPath/$blockName$pf";
		    }
		    else
		    {
			if ($compressBlock eq 'c')
			{
#print "-13- compressBlock = c, postfix = $postfix\n";
			    if ($direct and $compressCommand eq 'bzip2')
			    {
				my $bz = new IO::Compress::Bzip2(
				    "$targetDir/$blockFile$postfix",
				    BlockSize100K => 9);
				unless ($bz->syswrite($buffer))
				{
				    $prLog->print('-kind' => 'E',
						  '-str' =>
			  ["writing compressed data failed " .
			   "<$targetDir/$blockFile$postfix>"]);
				}
				$bz->flush();
				$bz->eof();

				$statSizeNew +=
				    (stat("$targetDir/$blockFile$postfix"))[7] || 0;
			    }
			    else
			    {
#print "C\n";
				$paralFork->add_noblock(
				    '-function' => \&compressOneBlock,
				    '-funcPar' =>
				    [$buffer,
				     "$targetDir/$blockFile$postfix",
				     $compressCommand,
				     $compressOptions,
				     $prLog, $tmpdir],
				    '-info' => [$digest,
						"$relPath/$blockName",
						$postfix]);
				++$statNoForksCompress;
			    }
			    push @newMD5line,
				"$digest $compressBlock $relPath/$blockName$postfix";
			}
			else
			{
#print "-14- compressBlock = u\n";
			    if ($direct)
			    {
				::copyOneBlock($buffer, "$targetDir/$blockFile",
					       $prLog);
				$statSizeNew += (stat("$targetDir/$blockFile"))[7] || 0;
			    }
			    else
			    {
#print "D\n";
				$paralFork->add_noblock('-function' => \&copyOneBlock,
							'-funcPar' =>
							[$buffer,
							 "$targetDir/$blockFile",
							 $prLog],
							'-info' => [$digest,
							       "$relPath/$blockName",
								    '']);
			    ++$statNoForksCP;
			    }
			    push @newMD5line,
				"$digest $compressBlock $relPath/$blockName";
			}
		    }
#print "-15- md5 $relPath/$blockName\n";
		}
		$tinySched->reset();
	    }
	    else
	    {
		$jobToDo = 0;
	    }
	}

	#############################
	$tinySched->wait();

	$parForkToDo = $paralFork->getNoUsedEntries();
    }

    if ($fileIn)
    {
	my $out = $fileIn->getSTDERR();
	if (@$out)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["reading from $sourceDir generated",
				     @$out]);
	    ++$noErrors;
	    return 0;
	}
	$fileIn->close();
	$fileIn = undef;
    }
    else
    {
	close(FILE);
    }


    if ($ctime != 0)    # not a device
    {
	unless (-e $sourceDir)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["<$sourceDir> deleted during backup"])
		unless exists $suppressWarning{'fileChange'};
	    ++$noErrors;
	}
	else
	{
	    my ($actMtime, $actCtime) = (stat($sourceDir))[9,10];
	    if ($actMtime != $mtime or $actCtime != $ctime)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["<$sourceDir> changed during backup"])
		    unless exists $suppressWarning{'fileChange'};
		++$noWarnings;
	    }
	}
    }

#    if (not $lateLinks or $mkdirLateLinksFilePath)
    {
	my $csf = "$targetDir/$relPath/$blockCheckSumFile.bz2";
	my $csfWrite = pipeToFork->new('-exec' => 'bzip2',
				       '-stdout' => $csf,
				       '-outRandom' => "$tmpdir/stbuPipeTo10-",
				       '-delStdout' => 'no',
				       '-prLog' => $prLog);
	++$statNoForksCompress;

	my ($line);
	foreach $line (@newMD5line)
	{
	    # write to temporary file
	    print OUT "$line\n";
	    #write to block local .md5CheckSum
	    $csfWrite->print("$line\n");
	}

	$csfWrite->wait();
	my $out = $csfWrite->getSTDERR();
	if (@$out)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["bzip2 reports errors:",
				     @$out]);
	    return 0;
	}
	$csfWrite->close();
    }

    # 'md5 of whole file', 'size of orig', 'size of blocks'
    my $md5 = $md5All->hexdigest();
    print OUT "allMD5 $md5 $statSizeOrig $statSizeNew " .
	"$statNoForksCP $statNoForksCompress $blockNo $statNoLateLinks " .
	"$noWarnings $noErrors $noBlockComprCheckCompr $noBlockComprCheckCp\n";
    close(OUT);

    return 0;
}


##################################################
# schreibt neue Meta-Informationen in dbms + .md5CheckSum
package aktFilename;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-infoFile'        => undef,
		    '-blockCheckSumFile' => undef,
		    '-compressMD5File' => undef,
		    '-sourceDir'       => undef,
		    '-followLinks'     => undef,
		    '-compress'        => undef,
		    '-uncompress'      => undef,
		    '-postfix'         => undef,
		    '-exceptDirs'      => [],
		    '-includeDirs'     => [],
		    '-comprRule'       => [],
		    '-exceptRule'      => [],
		    '-includeRule'     => [],
		    '-writeExcludeLog' => undef,
		    '-exceptTypes'     => undef,
		    '-specialTypeArchiver' => undef,
		    '-archiveTypes'    => undef,
		    '-checkBlocksRule' => [],
		    '-checkBlocksBS'   => [],
		    '-checkBlocksCompr'=> [],
		    '-checkBlocksRead' => [],
		    '-checkDevices'    => [],
		    '-checkDevicesDir' => [],
		    '-checkDevicesBS'  => [],
		    '-checkDevicesCompr' => [],
		    '-lateLinks'       => undef,
		    '-logInBackupDir'  => undef,
		    '-compressLogInBackupDir' => undef,
		    '-logInBackupDirFileName' => undef,
		    '-aktDate'         => undef,
		    '-prLog'           => undef,
		    '-chmodMD5File'    => undef,
		    '-indexDir'        => undef,
		    '-debugMode'       => 'no');

    &::checkObjectParams(\%params, \@_, 'aktFilename::new',
			 ['-infoFile', '-blockCheckSumFile',
			  '-compressMD5File', '-sourceDir', '-followLinks',
			  '-compress', '-uncompress', '-postfix',
			  '-exceptDirs', '-comprRule',
			  '-includeDirs', '-exceptRule', '-exceptTypes',
			  '-specialTypeArchiver', '-archiveTypes',
			  '-includeRule', '-checkBlocksRule',
			  '-checkBlocksBS', '-checkBlocksCompr',
			  '-checkBlocksRead',
			  '-checkDevicesBS', '-checkDevices',
			  '-checkDevicesDir',
			  '-checkDevicesCompr', '-aktDate',
			  '-prLog', '-chmodMD5File', '-indexDir']);
    &::setParamsDirect($self, \%params);

    my $prLog = $self->{'prLog'};

    my $exceptRule = $self->{'exceptRule'}->hasLine() ?
	"'" . join("' '", @{$self->{'exceptRule'}->getLine()}) . "'" : '';
    my $includeRule = $self->{'includeRule'}->hasLine() ?
	"'" . join("' '", @{$self->{'includeRule'}->getLine()}) . "'" : '';
    my $comprRule = $self->{'comprRule'}->hasLine() ?
	"'" . join("' '", @{$self->{'comprRule'}->getLine()}) . "'" : '';
    my $exceptDirs = @{$self->{'exceptDirs'}} ?
	"'" . join("' '", @{$self->{'exceptDirs'}}) . "'" : '';
    $exceptDirs =~ s/\\/\\5C/og;    # '\\' stored as \5C
    $exceptDirs =~ s/\n/\\0A/sog;   # '\n' stored as \0A
    my $includeDirs = @{$self->{'includeDirs'}} ?
	"'" . join("' '", @{$self->{'includeDirs'}}) . "'" : '';
    $includeDirs =~ s/\\/\\5C/og;    # '\\' stored as \5C
    $includeDirs =~ s/\n/\\0A/sog;   # '\n' stored as \0A
    my $exceptTypes = $self->{'exceptTypes'} ? $self->{'exceptTypes'} : '';
    if ($specialTypeArchiver)
    {
	$archiveTypes = '' unless $archiveTypes;
    }
    else
    {
	$specialTypeArchiver = '';
	$archiveTypes = '';
    }
    my $sd = $self->{'sourceDir'};
    $sd =~ s/\\/\\5C/og;    # '\\' stored as \5C
    $sd =~ s/\n/\\0A/sog;   # '\n' stored as \0A
    $sd =~ s/\'/\\\'/sog;   # ' stored as \'
    my $logInBackupDirFileName = $self->{'logInBackupDirFileName'};
    $logInBackupDirFileName =~ s/\\/\\5C/og;    # '\\' stored as \5C
    $logInBackupDirFileName =~ s/\n/\\0A/sog;   # '\n' stored as \0A
    $logInBackupDirFileName =~ s/\'/\\\'/sog;   # ' stored as \'

    my (@blocksRules, $i);
    my $checkBlocksRule = $self->{'checkBlocksRule'};
    my $checkBlocksBS = $self->{'checkBlocksBS'};
    foreach $i (0..@$checkBlocksRule-1)
    {
	my $br = "checkBlocksRule$i=";
	my $bs = "checkBlocksBS$i=";
	my $bc = "checkBlocksCompr$i=";
	my $bread = "checkBlocksRead$i=";

	my (@cbr) = @$checkBlocksRule;
	if (defined $cbr[$i])
	{
	    $br .= "'" . join(' ', @{$cbr[$i]}) . "'";
	    $bs .= $$checkBlocksBS[$i];
	    $bc .= $checkBlocksCompr[$i];
	    $bread .= $checkBlocksRead[$i]
		? "'" . join(' ', @{$checkBlocksRead[$i]}) . "'" : '';
	}
	$br =~ s/\\/\\5C/og;    # '\\' stored as \5C
	$br =~ s/\n/\\0A/sog;   # '\n' stored as \0A
	push @blocksRules, $br, $bs, $bc, $bread;
    }
    my (@devices);
    my $checkDevices = $self->{'checkDevices'};
    my $checkDevicesDir = $self->{'checkDevicesDir'};
    my $checkDevicesBS = $self->{'checkDevicesBS'};
    my $checkDevicesCompr = $self->{'checkDevicesCompr'};
    foreach $i (0..@$checkDevices-1)
    {
	push @devices,
	"checkDevices$i=" . $checkDevices[$i],
	"checkDevicesDir$i=" . $checkDevicesDir[$i],
	"checkDevicesBS$i=" . $checkDevicesBS[$i],
	"checkDevicesCompr$i=" . $checkDevicesCompr[$i];
    }
    my (@infoLines) = ("version=" . $main::checkSumFileVersion,
		       "storeBackupVersion=" . $main::STOREBACKUPVERSION,
		       "date=" .
		       $self->{'aktDate'}->getDateTime('-format' =>
						       '%Y.%M.%D %h.%m.%s'),
		       "sourceDir=" . "'" . $sd . "'",
		       "followLinks=" . $self->{'followLinks'},
		       "compress=" .
		       "'" . join("' '", @{$self->{'compress'}}) . "'",
		       "uncompress=" .
		       "'" . join("' '", @{$self->{'uncompress'}}) . "'",
		       "postfix=" . "'" . $self->{'postfix'} . "'",
		       "comprRule=" . $comprRule,
		       "exceptDirs=" . $exceptDirs,
		       "includeDirs=" . $includeDirs,
		       "exceptRule=" . $exceptRule,
		       "includeRule=" . $includeRule,
		       "writeExcludeLog=" .
		           ($self->{'writeExcludeLog'} ? 'yes' : 'no'),
		       "exceptTypes=" . $exceptTypes,
		       "archiveTypes=" . $archiveTypes,
		       "specialTypeArchiver=" . $specialTypeArchiver,
		       @blocksRules,
		       @devices,
		       "preservePerms=" . ($preservePerms ? 'yes' : 'no'),
		       "lateLinks=". ($lateLinks ? 'yes' : 'no'),
		       "lateCompress=" . ($lateCompress ? 'yes' : 'no'),
		       "cpIsGnu=". ($gnucp ? 'yes' : 'no'),
		       "logInBackupDir=" .
		           ($self->{'logInBackupDir'} ? 'yes' : 'no'),
		       "compressLogInBackupDir=" .
		           ($self->{'compressLogInBackupDir'} ? 'yes' : 'no'),
		       "logInBackupDirFileName=" .
		           "'" . $logInBackupDirFileName . "'",
		       "linkToRecent=" .
		           ($linkToRecent ? "'" . $linkToRecent . "'" : "")
		       );
    my $infoFile = $self->{'infoFile'};

    my $wcsf = writeCheckSumFile->new('-checkSumFile' => $infoFile,
				      '-blockCheckSumFile' =>
				      $self->{'blockCheckSumFile'},
				      '-infoLines' => \@infoLines,
				      '-prLog' => $prLog,
				      '-chmodMD5File' => $self->{'chmodMD5File'},
				      '-compressMD5File' =>
				      $self->{'compressMD5File'},
				      '-lateLinks' => $lateLinks,
				      '-tmpdir' => $tmpdir);
    $self->{'writeCheckSumFile'} = $wcsf;

    bless $self, $class;
}


########################################
sub setDBMmd5
{
    my $self = shift;

    $self->{'DBMmd5'} = shift;
}


########################################
# für normale Dateien
sub store
{
    my $self = shift;

    my (%params) = ('-filename'    => undef,
		    '-md5sum'      => undef,
		    '-compr'       => undef,
		    '-dev'         => undef,
		    '-inode'       => undef,
		    '-inodeBackup' => undef,
		    '-ctime'       => undef,
		    '-mtime'       => undef,
		    '-atime'       => undef,
		    '-size'        => undef,
		    '-uid'         => undef,
		    '-gid'         => undef,
		    '-mode'        => undef,
		    '-storeInDBM'  => 1      # Default: speichern,
		                             #        0 = nicht speichern
		    );

    &::checkObjectParams(\%params, \@_, 'aktFilename::store',
			 ['-filename', '-md5sum', '-compr', '-dev', '-inode',
			  '-inodeBackup', '-ctime', '-mtime', '-atime',
			  '-size', '-uid', '-gid', '-mode']);
    my $filename = $params{'-filename'};
    my $md5sum = $params{'-md5sum'};
    my $compr = $params{'-compr'};
    my $dev = $params{'-dev'};
    my $inode = $params{'-inode'};
    my $inodeBackup = $params{'-inodeBackup'};
    my $ctime = $params{'-ctime'};
    my $mtime = $params{'-mtime'};
    my $atime = $params{'-atime'};
    my $size = $params{'-size'};
    my $uid = $params{'-uid'};
    my $gid = $params{'-gid'};
    my $mode = $params{'-mode'};

    if ($params{'-storeInDBM'})
    {
	my $DBMmd5 = $self->{'DBMmd5'};

	my $md5pack = pack('H32', $md5sum);
	my $f = $self->{'indexDir'}->setIndex($filename);
	$$DBMmd5{$md5pack} = pack('FaSa*', $inodeBackup, $compr,
				  0, $f)
	    unless exists $$DBMmd5{$md5pack};
    }	                            # $backupDirIndex ist immer 0

    $self->{'writeCheckSumFile'}->write('-filename' => $filename,
					'-md5sum' => $md5sum,
					'-compr' => $compr,
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => $inodeBackup,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => $size,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => $mode
					);
}


########################################
sub storeDir
{
    my $self = shift;

    my (%params) = ('-dir'   => undef,
		    '-dev'   => undef,
		    '-inode' => undef,
		    '-ctime' => undef,
		    '-mtime' => undef,
		    '-atime' => undef,
		    '-uid'   => undef,
		    '-gid'   => undef,
		    '-mode'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'aktFilename::storeDir',
			 ['-dir', '-dev', '-inode', '-ctime', '-mtime',
			  '-atime', '-uid', '-gid', '-mode']);

    my $dir = $params{'-dir'};
    my $dev = $params{'-dev'};
    my $inode = $params{'-inode'};
    my $ctime = $params{'-ctime'};
    my $mtime = $params{'-mtime'};
    my $atime = $params{'-atime'};
    my $uid = $params{'-uid'};
    my $gid = $params{'-gid'};
    my $mode = $params{'-mode'};

    my $inodeBackup = 0;    # irrelevant

    $self->{'writeCheckSumFile'}->write('-filename' => $dir,
					'-md5sum' => 'dir',
					'-compr' => 0,
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => $inodeBackup,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => 0,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => $mode
					);
}


########################################
sub storeSymlink
{
    my $self = shift;

    my (%params) = ('-symlink' => undef,
		    '-dev'   => undef,
		    '-inode' => undef,
		    '-ctime'   => undef,
		    '-mtime'   => undef,
		    '-atime'   => undef,
		    '-uid'     => undef,
		    '-gid'     => undef,
		    );

    &::checkObjectParams(\%params, \@_, 'aktFilename::storeSymlink',
			 ['-symlink', '-dev', '-inode', '-ctime', '-mtime',
			  '-atime', '-uid', '-gid']);

    my $symlink = $params{'-symlink'};
    my $dev = $params{'-dev'};
    my $inode = $params{'-inode'};
    my $ctime = $params{'-ctime'};
    my $mtime = $params{'-mtime'};
    my $atime = $params{'-atime'};
    my $uid = $params{'-uid'};
    my $gid = $params{'-gid'};

    my $inodeBackup = 0;   # irrelevant

    $self->{'writeCheckSumFile'}->write('-filename' => $symlink,
					'-md5sum' => 'symlink',
					'-compr' => 0,
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => $inodeBackup,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => 0,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => 0
					);
}


########################################
sub storeNamedPipe
{
    my $self = shift;

    my (%params) = ('-pipe'  => undef,
		    '-dev'   => undef,
		    '-inode' => undef,
		    '-ctime' => undef,
		    '-mtime' => undef,
		    '-atime' => undef,
		    '-uid'   => undef,
		    '-gid'   => undef,
		    '-mode'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'aktFilename::storeNamedPipe',
			 ['-pipe', '-ctime', '-mtime', '-atime',
			  '-uid', '-gid', '-mode']);

    my $pipe = $params{'-pipe'};
    my $dev = $params{'-dev'};
    my $inode = $params{'-inode'};
    my $ctime = $params{'-ctime'};
    my $mtime = $params{'-mtime'};
    my $atime = $params{'-atime'};
    my $uid = $params{'-uid'};
    my $gid = $params{'-gid'};
    my $mode = $params{'-mode'};

    my $inodeBackup = 0;   # irrelevant

    $self->{'writeCheckSumFile'}->write('-filename' => $pipe,
					'-md5sum' => 'pipe',
					'-compr' => 0,
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => $inodeBackup,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => 0,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => $mode
					);
}


########################################
sub storeSpecial
{
    my $self = shift;

    my (%params) = ('-name'  => undef,
                    '-type'  => undef,
		    '-dev'   => undef,
		    '-inode' => undef,
		    '-ctime' => undef,
		    '-mtime' => undef,
		    '-atime' => undef,
		    '-uid'   => undef,
		    '-gid'   => undef,
		    '-mode'  => undef
		    );

    &::checkObjectParams(\%params, \@_, 'aktFilename::storeSpecial',
			 ['-name', '-ctime', '-mtime', '-atime',
			  '-uid', '-gid', '-mode', '-type']);

    my $name = $params{'-name'};
    my $type = $params{'-type'};
    my $dev = $params{'-dev'};
    my $inode = $params{'-inode'};
    my $ctime = $params{'-ctime'};
    my $mtime = $params{'-mtime'};
    my $atime = $params{'-atime'};
    my $uid = $params{'-uid'};
    my $gid = $params{'-gid'};
    my $mode = $params{'-mode'};

    my $inodeBackup = 0;   # irrelevant

    $type = "socket" if $type eq "S";
    $type = "blockdev" if $type eq "b";
    $type = "chardev" if $type eq "c";

    $self->{'writeCheckSumFile'}->write('-filename' => $name,
					'-md5sum' => $type,
					'-compr' => 'u',
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => $inodeBackup,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => 0,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => $mode
					);
}



########################################
# for signal handling
sub delInfoFile
{
    my $self = shift;

    unlink $self->{'infoFile'};
}


########################################
sub closeInfoFile
{
    my $self = shift;

    $self->{'writeCheckSumFile'}->destroy();
}


##################################################
package readDirCheckSizeTime;
our @ISA = qw( recursiveReadDir );

########################################
sub new
{
    my $class = shift;

    my (%params) = ('-dir'            => undef, # zu durchsuchendes directory
		    '-adminDirs'      => undef, # Objekt mit Infos von
		                                # Verzeichnissen
		    '-oldFilename'    => undef, # Objekt mit alten DBMs etc.
		    '-aktFilename'    => undef, # Objekt für neue Meta Infos
		    '-aktDir'         => undef, # zu sicherndes Directory
		    '-followLinks'    => 0,     # Tiefe, bis zu der symlinks
		                                # gefolgt werden soll
		    '-exceptDirs'     => [],    # Ausnahmeverzeichnisse
		    '-includeDirs'    => [],    # only include these dirs
		    '-stayInFileSystem' => 0,   # don't leave file system, but
		                                # consider --followLinks
		    '-postfix'        => undef, # Postfix, der nach Kompr.
		                                # angehängt werden soll
		    '-includeRule'    => undef,
		    '-exceptRule'     => undef,
		    '-checkBlocksRule' => undef,
		    '-writeExcludeLog'=> undef,
		    '-exTypes'        => undef,
		    '-resetAtime'     => undef,
                    '-cpIsGnu'        => undef,
		    '-debugMode'      => undef,
		    '-verbose'        => undef,
		    '-tmpdir'         => undef,
		    '-prLog'          => undef,
		    '-prLogError'     => 'E',
		    '-prLogWarn'      => 'W',
		    '-exitIfError'    => 1,      # Errorcode bei Fehler
		    '-ignoreReadError' => 'no',
		    '-ignoreTime'     => 'none',
		    '-printDepth'     => undef
		    );

    &::checkObjectParams(\%params, \@_, 'readDirCheckSizeTime::new',
			 ['-dir', '-oldFilename', '-aktDir', '-exTypes',
			  '-postfix', '-adminDirs', '-prLog',
			  '-printDepth']);

    if (defined $params{-dir})
    {
	$params{'-dir'} =~ s/\/\//\//g;        # // -> /
	$params{'-dir'} =~ s/\A(.+)\/\Z/$1/;   # remove trailing /
    }

    my $self = recursiveReadDir->new('-dirs' => [$params{'-dir'}],
				     '-followLinks' => $params{'-followLinks'},
				     '-stayInFileSystem' =>
				         $params{'-stayInFileSystem'},
				     '-exceptDirs' => $params{'-exceptDirs'},
				     '-includeDirs' => $params{'-includeDirs'},
				     '-prLog' => $params{'-prLog'},
				     '-prLogError' => $params{'-prLogError'},
				     '-prLogWarn' => $params{'-prLogWarn'},
				     '-verbose' => $params{'-verbose'},
				     '-exitIfError' => $params{'-exitIfError'},
				     '-printDepth' => $params{'-printDepth'},
				     '-printDepthPrlogKind' => 'P'
				     );
    &::setParamsDirect($self, \%params);
    $self->{'aktInfoFile'} = $params{'-adminDirs'}->getAktInfoFile();

    $self->{'md5Fork'} = undef;      # es läuft kein paralleles md5sum

    if ($self->{'writeExcludeLog'})
    {
	my $wcl = $self->{'writeExcludeLog'};
	my $exclLog = pipeToFork->new('-exec' => 'bzip2',
				      '-stdout' => $wcl,
				      '-outRandom' => "$tmpdir/stbuPipeTo11-",
				      '-delStdout' => 'no',
				      '-prLog' => $prLog);
	$self->{'exclLog'} = $exclLog;
    }

    bless $self, $class;
}


########################################
# liefert Basisverzeichnis, dazu relativen Dateinamen und Filetyp
sub next
{
    my $self = shift;

    my ($f, $types);
    my $n = ($f, $types) = $self->recursiveReadDir::next();

    if ($self->{'md5Fork'} and $n == 0)
    {
        # If there were no dir's left to check, readDir may not have
        # been called by the next() call above. We have to call it
        # manually to check whether the md5 process is finished (and
        # if so, retrieve the results)
	$self->readDir();
	return () if (@{$self->{'files'}} == 0);
        $f = shift @{$self->{'files'}};
	$types = shift @{$self->{'types'}};
    }
    elsif ($n == 0)
    {
	return ();
    }

    my $md5 = shift @{$self->{'md5'}};
    # $f zerlegen in vorgegebenen Teil und relativen
    my $dir = $self->{'dir'};
    my $file = &::substractPath($f, $dir);

    return ($dir, $file, $md5, $types);
}


########################################
# wird von %inProgress in Scheduler::normalOperation benötigt
sub pushback
{
    my $self = shift;
    my $list = shift;     # Liste mit Listen von ($dir, $file, $md5, $types)
    my $prLog = shift;
    my $debug = shift;

    my $l;
    foreach $l (@$list)
    {
	my ($dir, $file, $md5, $type) = (@$l);
	$prLog->print('-kind' => 'D',
		      '-str' => ["checking of identical file <$file>"])
	    if $debug;
	push @{$self->{'files'}}, "$dir/$file";
	push @{$self->{'md5'}}, $md5;
	push @{$self->{'types'}}, $type;
    }
}


########################################
sub readDir
{
    my $self = shift;

    my $prLog = $self->{'prLog'};
    my $postfix = $self->{'postfix'};
    my $aktFilename = $self->{'aktFilename'};
    my $debugMode = $self->{'debugMode'};
    my $verbose = $self->{'verbose'};
    my $gnucp = $self->{'cpIsGnu'};

    my $exceptRule = $self->{'exceptRule'};
    my $includeRule = $self->{'includeRule'};
    my $checkBlocksRule = $self->{'checkBlocksRule'};
    my $exinclPattFlag =
	$exceptRule->hasLine() + $includeRule->hasLine();
    my $exTypes = $self->{'exTypes'};
    my $writeExcludeLog = $self->{'writeExcludeLog'};
    my $exclLog = $self->{'exclLog'} if $writeExcludeLog;

    my (@files) = ();
    my (@md5) = ();
    my (@types) = ();

    my $oldFilename = $self->{'oldFilename'};
    my $tmpdir = $self->{'tmpdir'};
    my $ignoreTime = $self->{'ignoreTime'};


    # MD5 läuft, wenn möglich MD5 Summen vom Parallelprozess holen
    if ($self->{'md5Fork'} and
        not $self->{'md5Fork'}->processRuns())
    {
        my $stderr = $self->{'md5Fork'}->getSTDERR();
        my($l);
        $prLog->print('-kind' => 'E',
                      '-str' =>
                      ["fork of md5sum generated the following errors:",
                       @$stderr])
            if (@$stderr > 0);
        my $stdout = $self->{'md5Fork'}->getSTDOUT();
        foreach $l (@$stdout)
        {
            if ($l =~ /\A\\/)  # "\" am Zeilenanfang -> es wird gequotet
            {
                $l =~ s/\\n/\n/g;   # "\n" im Namen wird von md5sum zu
                                    # "\\n" gemacht,
                                    # zurückkonvertieren!
                $l =~ s/\\\\/\\/og; # Backslash
                $l =~ s/\A\\//;     # "\\" am Zeilenanfang entfernen

            }
            my ($md5, $f) = $l =~ /\A(\w+)\s+(.*)/s;
            push @files, $f;
            push @md5, $md5;
            push @types, 'f';
        }
        $self->{'md5Fork'} = undef;  # job ist fertig
    }

    # Neuen MD5 Lauf starten wenn möglich
    if (not $self->{'md5Fork'})
    {
        my(@calcMD5) = ();

	# Directory einlesen
        $self->recursiveReadDir::readDir();

	# Eingelesene Dateien in $self->{'files'} filtern
        my ($f, $t, $i);
        my $dir = $self->{'dir'};     # zu durchsuchendes Directory

        my $aktDir = $self->{'aktDir'};   # aktuelles Backupverzeichnis
	for ($i = 0 ; $i < @{$self->{'files'}} ; $i++)
	{
	    $f = $self->{'files'}[$i];
	    $t = $self->{'types'}[$i];

	    my $relFileName;
	    if ($dir eq '/')
	    {
		$relFileName = substr($f, 1);
	    }
	    else
	    {
		$relFileName = substr($f, length($dir) + 1);
	    }
	    $relFileName =~ s#\A/+##;   # remove leading / if exists

	    if (exists $$exTypes{$t})
	    {
		++$$exTypes{$t};
		$prLog->print('-kind' => 'D',
			      '-str' => ["exceptType $t <$relFileName>"])
		    if $debug > 0;
		next;
	    }

	    if ($t eq 'S' and
                not $gnucp)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["unsupported file type 'socket'" .
					 " <$relFileName>",
			  "\tsee option 'cpIsGnu' or 'specialTypeArchiver'"]);
		next;
	    }
	    if ($t eq 'b' and
		not $gnucp)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["unsupported file type 'block " .
					 "special file' <$relFileName>",
		          "\tsee option 'cpIsGnu' or 'specialTypeArchiver'"]);
		next;
	    }
	    if ($t eq 'c' and
               not $gnucp)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["unsupported file type 'character '" .
					 "special file' <$relFileName>",
			  "\tsee option 'cpIsGnu' or 'specialTypeArchiver'"]);
		next;
	    }

	    unless (-e $f)
	    {
		unless (-l $f)
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["file <$f> deleted during backup (1)"])
			unless exists $suppressWarning{'fileChange'};
		    next;
		}
	    }
	    my ($dev, $inode, $mode, $uid, $gid, $actCtime, $actMtime,
		$actAtime, $actSize) =
		    (stat($f))[0, 1, 2, 4, 5, 10, 9, 8, 7];
	    $mode = 0 unless $mode;
	    $mode &= 07777;
	    # check exceptRule and includeRule
	    if ($t ne 'd' and $exinclPattFlag)
	    {
		if ($exceptRule->hasLine() == 1 and
		    $exceptRule->checkRule($relFileName, $actSize, $mode,
					   $actCtime, $actMtime, $uid,
					   $gid, $t) == 1)
		{
		    $exclLog->print("$relFileName\n") if $writeExcludeLog;
#print "f = <$f> size = $actSize\n";
		    $actSize = 0 unless defined $actSize; # excluded with MARK_DIR_REC
		    $main::stat->incr_noExcludeRule($actSize);
		    next;
		}

		if ($includeRule->hasLine() == 1)
		{
		    if ($includeRule->checkRule($relFileName, $actSize, $mode,
					    $actCtime, $actMtime, $uid,
					    $gid, $t) == 1)
		    {
			$exclLog->print("$relFileName\n") if $writeExcludeLog;
			$main::stat->incr_noIncludeRule($actSize);
		    }
		    else
		    {
			next;
		    }
		}
	    }

            # Nicht plain-file benötigt kein MD5
	    if ($t ne 'f')
	    {
		push @files, $f;
		push @types, $t;
                push @md5, undef;
		next;
	    }


	    #
	    # ab hier ist alles nur noch plain file (in for Schleife)
	    #
	    my ($oldCompr, $oldCtime, $oldMtime, $oldSize, $md5sum);
	    my $n = ($oldCompr, $oldCtime, $oldMtime, $oldSize, $md5sum) =
		$oldFilename->getInodebackupComprCtimeMtimeSizeMD5($relFileName);

	    # check checkBlocksRule
	    if ($t eq 'f' and $checkBlocksRule->hasLine()) # this line results
	    {                        # in a warning due to a bug in perl
		my ($ruleBS, $ruleCompress, $ruleParallel, $ruleRead) =
		    $checkBlocksRule->checkRule($relFileName, $actSize,
						$mode, $actCtime,
						$actMtime, $uid,
						$gid, $t);
		if ($ruleBS > 0)
		{
		    # md5 is calculated later
		    push @files, $f;
		    push @types, 'bf';   # block file

		    if ($n > 0 and
			$actSize == $oldSize and
			($actMtime == $oldMtime) and
			($oldCompr eq 'b'))
		    {
			# nothing changed
			push @md5, $md5sum;
		    }
		    else
		    {
#			my $c = $ruleCompress ? 'c' : 'u';
			my $c = $ruleCompress;
			                                 # calculate new md5 sum
			push @md5, [$ruleBS, $c, $ruleParallel, @$ruleRead];
			if ($debugMode >= 3)
			{
			    my (@reason);
			    push @reason, 'size' if $actSize != $oldSize;
			    push @reason, 'mtime' if $actMtime != $oldMtime;
			    push @reason, 'ctime' if $actCtime != $oldCtime;
			    $prLog->print('-kind' => 'D',
					  '-str' => ["md5sum (" .
					  join(', ', @reason) . ") $f"]);
			}
		    }
		    next;
		}
	    }
	    elsif ($oldCompr and $oldCompr eq 'b')    # f -> b
	    {
		push @types, 'fnew';   # force copy or compress, do not
		push @md5, $md5sum;    # link because previous backup was
		push @files, $f;       # blocked
		if ($debugMode >= 3)
		{
		    $prLog->print('-kind' => 'D',
				  '-str' => ["md5sum (block to file) $f"]);
		}
		next;
	    }

	    # plain files, no blocked files
	    if ($n == 0)    # nicht im Hash gefunden (aus Datei .md5CheckSums
	    {               # -> näher untersuchen!
                $prLog->print('-kind' => 'I',
                              '-str' =>
                              ["Checking $relFileName [new]"]) if $verbose;
		push @calcMD5, $f;
		if ($debugMode >= 3)
		{
		    $prLog->print('-kind' => 'D',
				  '-str' => ["md5sum (new file) $f"]);
		}
		next;
	    }

	    if ($ignoreTime ne 'mtime' and ($actMtime != $oldMtime))
	    {
                $prLog->print('-kind' => 'I',
                              '-str' =>
                              ["Checking $relFileName [mtime: $oldMtime -> $actMtime]"])
		    if $verbose;
		push @calcMD5, $f;
		if ($debugMode >= 3)
		{
		    $prLog->print('-kind' => 'D',
				  '-str' => ["md5sum (mtime) $f"]);
		}
		next;
	    }

            elsif ($actSize != $oldSize)
	    {
		push @calcMD5, $f;
		if ($debugMode >= 3)
		{
		    $prLog->print('-kind' => 'D',
				  '-str' => ["md5sum (size) $f"]);
		}
		next;
	    }

	    elsif ($ignoreTime ne 'ctime' and ($actCtime != $oldCtime))
	    {
                $prLog->print('-kind' => 'I',
                              '-str' =>
                              ["Checking $relFileName [ctime: $oldCtime -> $actCtime]"])
		    if $verbose;
		push @calcMD5, $f;
		if ($debugMode >= 3)
		{
		    $prLog->print('-kind' => 'D',
				  '-str' => ["md5sum (ctime) $f"]);
		}
		next;
	    }


	    #
	    # übrig: plain files, die sich gegenüber dem letzten Backup
	    # nicht verändert haben
	    #

            # mit md5 Summe über dbm(md5) gehen, dadurch
            # Doppelte vermeiden
            push @files, $f;
            push @md5, $md5sum;
            push @types, 'f';
	}


        # Parallelprozess starten,
        # MD5 Summen für @calcMD5 berechnen
        if (@calcMD5 > 0)
        {
            $self->{'md5Fork'} = forkMD5->new('-param' => [@calcMD5],
					      '-prLog' => $prLog,
					      '-tmpdir' => $tmpdir,
					      '-resetAtime' =>
					      $self->{'resetAtime'});
        }
    }

    # Falls noch ein Parallelprozess läuft, sicherstellen dass readDir
    # erneut aufgerufen wird auch wenn es jetzt nichts zurückgegeben
    # hat.
    if (@files == 0 and $self->{'md5Fork'})
    {
        push @files, undef;
        push @md5, undef;
        push @types, 'repeat';
    }

    $self->{'files'} = \@files;
    $self->{'md5'} = \@md5;
    $self->{'types'} = \@types;
}


########################################
sub DESTROY
{
    my $self = shift;

    my $wcl = $self->{'writeExcludeLog'};

    if ($wcl and $main::endOfStoreBackup)
    {
#	local *EXCL_LOG = $self->{'EXCL_LOG'};
#	close(EXCL_LOG) or
#	    $self->{'prLog'}->print('-kind' => 'E',
#				    '-str' => ["cannot close <$wcl>"],
#				    '-exit' => 1);
	my $exclLog = $self->{'exclLog'};
	$exclLog->wait();
	my $out = $exclLog->getSTDERR();
	if (@$out)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["bzip2 reports errors:",
				     @$out]);
	    exit 1;
	}
	$exclLog->close();
    }
}


##################################################
# stellt fest, welches das neue Directory ist, löscht alte
package adminDirectories;
use Carp;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-targetDir'    => undef,
		    '-checkSumFile' => undef,
		    '-tmpdir'       => undef,
		    '-chmodMD5File' => undef,
		    '-prLog'        => undef,
		    '-aktDate'      => undef,
		    '-debugMode'    => 0
		    );

    &::checkObjectParams(\%params, \@_, 'adminDirectories::new',
			 ['-targetDir', '-checkSumFile', '-chmodMD5File',
			  '-tmpdir', '-prLog']);
    &::setParamsDirect($self, \%params);

# weitere Variablen:
# 'aktDate', 'baseDir', 'aktDir', 'prevDir', 'oldDirs'

    my $targetDir = $self->{'targetDir'};
    my $chmodMD5File = $self->{'chmodMD5File'};
    my $prLog = $self->{'prLog'};

    my $aktDate = $self->{'aktDate'};
    $self->{'baseDir'} = $targetDir;
    my $aktDir = $self->{'aktDir'} = $targetDir . '/' .
	$aktDate->getDateTime('-format' => '%Y.%M.%D_%h.%m.%s');

    my $asbd = allStoreBackupSeries->new('-rootDir' => $targetDir,
					 '-checkSumFile' => $checkSumFile,
					 '-prLog' => $prLog);
    $self->{'prevDir'} = $asbd->getFinishedPrev();

# Neues Verzeichnis anlegen
    $prLog->print('-kind' => 'E',
		  '-str' => ["cannot create <$aktDir>, exiting"],
		  '-exit' => 1)
	unless (mkdir $aktDir);
    chmod 0755, $aktDir;
    my $chmodDir = $chmodMD5File;
    $chmodDir |= 0100 if $chmodDir & 0400;
    $chmodDir |= 0010 if $chmodDir & 0040;
    $chmodDir |= 0001 if $chmodDir & 0004;
    mkdir "$aktDir/.storeBackupLinks", $chmodDir;

    my $debugMode = $self->{'debugMode'};
    if ($debugMode > 0)
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["new directory is <$aktDir>",
				 $self->{'prevDir'} ?
				 "previous directory is <" .
				 $self->{'prevDir'} . ">" :
				 'no previous directory, first use']);
    }

    my (@oldDirs) = $asbd->getAllDirs();
    $self->{'oldDirs'} = \@oldDirs;

    bless $self, $class;
}


########################################
# sind sortiert: ältestes zuerst
sub getOldDirs
{
    my $self = shift;

    return $self->{'oldDirs'};
}


########################################
sub getAktDir
{
    my $self = shift;
    return $self->{'aktDir'};       # String
}


########################################
sub getAktInfoFile
{
    my $self = shift;

    my $aktDir = $self->{'aktDir'};
    if ($aktDir)
    {
	return $aktDir . '/' . $self->{'checkSumFile'};
    }
    else
    {
	return undef;
    }
}


########################################
sub getPrevDir
{
    carp "Deprecated! Why should this be neccessary?";
    my $self = shift;
    return $self->{'prevDir'};       # String
}


########################################
sub getOldInfoFile
{
    carp "Deprecated! Why should this be neccessary?";
    my $self = shift;

    my $prevDir = $self->{'prevDir'};
    if ($prevDir)
    {
	return $prevDir . '/' . $self->{'checkSumFile'};
    }
    else
    {
	return undef;
    }
}


##################################################
# Splittet die Parameterliste (falls zu lang) auf
# Stellt nach außen ein Interface analog forkProc zur Verfügung
# (läuft im Hintergrund als fork/exec)
# Arbeitet *alle* ab, erst dann wird Ergebnis geliefert
package forkMD5;

sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-param'      => [],
		    '-prLog'      => undef,
		    '-tmpdir'     => undef,
		    '-resetAtime' => undef
		    );

    &::checkObjectParams(\%params, \@_, 'forkMD5::new',
			 ['-prLog', '-tmpdir']);
    &::setParamsDirect($self, \%params);


    (@{$self->{'resultSTDERR'}}) = ();
    (@{$self->{'resultSTDOUT'}}) = ();

    bless $self, $class;

    # cache atime and mtime in object
    my (@atime, @mtime, $p);
    foreach $p (@{$self->{'param'}})
    {
	my ($atime, $mtime) = (stat($p))[8, 9];
	push @atime, $atime;
	push @mtime, $mtime;
    }

    # store information to restore atime (and mtime)
    @{$self->{'allParam'}} = @{$self->{'param'}};
    $self->{'atime'} = \@atime;
    $self->{'mtime'} = \@mtime;

    $self->_startJob();

    return $self;
}


########################################
sub _startJob
{
    my $self = shift;

    $self->{'fork'} = undef;

    my $prLog = $self->{'prLog'};

    do
    {
	my $l = 0;      # akkumulierte Länge der Paramter in Byte
	my $i;
	my $param = $self->{'param'};    # Pointer auf Parameter Vektor

	for ($i = 0 ; $i < @$param ; $i++)
	{
	    my $l1 = 1 + length $$param[$i];    # 1 Byte für '\0' in C
	    if ($l + $l1 > $main::execParamLength)
	    {
		last;
	    }
	    $l += $l1;
	}

	if ($i == 0)      # der erste paßt überhaupt nicht rein
	{                 # (ist alleine schon zu lang)
	    my $aktPar = shift @{$self->{'param'}};   # erten "wegwerfen"
	    $prLog->print('-kind' => 'E',
			  '-str' => ["parameter to long: cannot exec " .
				     "md5sum $aktPar"]);
	    return if @{$self->{'param'}} == 0;
	}
	else         # ok, die möglichen aus dem großen Vektor rausholen
	{
	    my (@aktPar) = splice(@{$self->{'param'}}, 0, $i);
	    $main::stat->incr_noForksMD5();
	    $main::stat->add_noMD5edFiles(scalar @aktPar);
	    $self->{'fork'} = forkProc->new('-exec' => 'md5sum',
					    '-param' => [@aktPar],
					    '-prLog' => $prLog,
					    '-workingDir' => '.',
					    '-outRandom' =>
					    $self->{'tmpdir'} . '/fork-md5-');
	    # Anzahl Bytes berechnen
	    my $sum = 0;
	    my $p;
	    foreach $p (@aktPar)
	    {
		$sum += (stat($p))[7];
	    }
	    $main::stat->addSumMD5Sum($sum)
		if ($sum);
	    return;
	}

    } while ($self->{'fork'} == undef);
}



########################################
# returns 1 if process still running
# returns 0 if process is not running
sub processRuns
{
    my $self = shift;

    if ($self->{'fork'})    # Prozess noch nicht ausgewertet
    {
	if ($self->{'fork'}->processRuns())  # Job läuft noch
	{
	    return 1;
	}
	else                    # Job ist fertig
	{
	    push @{$self->{'resultSTDERR'}}, @{$self->{'fork'}->getSTDERR()};
	    push @{$self->{'resultSTDOUT'}}, @{$self->{'fork'}->getSTDOUT()};

	    if (@{$self->{'param'}} > 0)     # noch was übrig
	    {
		$self->_startJob();
		return 1;
	    }
	    else
	    {
		return 0;                   # fertig!
	    }
	}
    }
    else
    {
	return 0;
    }
}


########################################
sub getSTDERR
{
    my $self = shift;

    return $self->{'resultSTDERR'};
}


########################################
sub getSTDOUT
{
    my $self = shift;

    return $self->{'resultSTDOUT'};
}


########################################
sub DESTROY
{
    my $self = shift;

    my $atime = $self->{'atime'};
    my $mtime = $self->{'mtime'};
    my $param = $self->{'allParam'};
    my $i;
    for ($i = 0 ; $i < @$param ; $i++)
    {
	utime $$atime[$i], $$mtime[$i], $$param[$i]
	    if $self->{'resetAtime'};
    }
}

##################################################
package Scheduler;

use IO::File;
use strict;
use warnings;

sub new
{
    my $class = shift;

    my $self = {};

    my (%params) = ('-aktFilename'      => undef,
		    '-oldFilename'      => undef,
		    '-followLinks'      => undef,
		    '-prevBackupOwnSeries' => undef,
		    '-readDirAndCheck'  => undef,
		    '-setResetDirTimes' => undef,
		    '-parForkCopy'      => undef,
		    '-fifoCopy'         => undef,
		    '-parForkCompr'     => undef,
		    '-noCompress'       => undef,
		    '-fifoCompr'        => undef,
		    '-blockCheckSumFile'=> undef,
		    '-parForkBlock'     => undef,
		    '-fifoBlock'        => undef,
		    '-compress'         => undef,
		    '-lateLinks'        => undef,
		    '-lateCompress'     => undef,
                    '-cpIsGnu'          => undef,
		    '-linkSymlinks'     => undef,
		    '-suppressWarning'  => undef,
                    '-preservePerms'    => undef,
		    '-comprRule'     => undef,
		    '-postfix'          => undef,
		    '-targetDir'        => undef,
		    '-aktInfoFile'      => undef,
		    '-resetAtime'       => undef,
		    '-tmpdir'           => undef,
		    '-prLog'            => undef,
		    '-debugMode'        => 0
		    );

    &::checkObjectParams(\%params, \@_, 'Scheduler::new',
			 ['-aktFilename', '-oldFilename', '-followLinks',
			  '-prevBackupOwnSeries', '-readDirAndCheck',
			  '-setResetDirTimes', '-parForkCopy', '-fifoCopy',
			  '-parForkCompr', '-fifoCompr', '-suppressWarning',
			  '-comprRule', '-compress', '-postfix',
			  '-compress', '-postfix',
			  '-targetDir', '-aktInfoFile', '-resetAtime',
			  '-prLog', '-lateLinks', '-lateCompress']);
    &::setParamsDirect($self, \%params);

    my ($compressCommand, @options) = @{$params{'-compress'}};
    $self->{'compressCommand'} = $compressCommand;
    $self->{'compressOptions'} = \@options;

    bless $self, $class;
}


########################################
# Idee:
#    Überwachung der forks in parForkCopy und parForkCompr
#    Wenn diese mit neuen Daten gefüttert wurden, Auffüllen
#    von fifoCopy und fifoCompr über readDirAndCheck
sub normalOperation
{
    my $self = shift;

    my $aktFilename = $self->{'aktFilename'};
    my $oldFilename = $self->{'oldFilename'};
    my $followLinks = $self->{'followLinks'};
    my $prevBackupOwnSeries = $self->{'prevBackupOwnSeries'};
    my $readDirAndCheck = $self->{'readDirAndCheck'};
    my $setResetDirTimes = $self->{'setResetDirTimes'};
    my $parForkCopy = $self->{'parForkCopy'};
    my $fifoCopy = $self->{'fifoCopy'};
    my $parForkCompr = $self->{'parForkCompr'};
    my $fifoCompr = $self->{'fifoCompr'};
    my $blockCheckSumFile = $self->{'blockCheckSumFile'};
    my $parForkBlock = $self->{'parForkBlock'};
    my $fifoBlock = $self->{'fifoBlock'};
    my $compress = join(' ', @{$self->{'compress'}});
    my $compressCommand = $self->{'compressCommand'};
    my $compressOptions = $self->{'compressOptions'};
    my $postfix = $self->{'postfix'};
    my $comprRule = $self->{'comprRule'};
    my $targetDir = $self->{'targetDir'};
    my $aktInfoFile = $self->{'aktInfoFile'};
    my $resetAtime = $self->{'resetAtime'};
    my $tmpdir = $self->{'tmpdir'};
    my $prLog = $self->{'prLog'};
    my $debugMode = $self->{'debugMode'};
    my $gnucp = $self->{'cpIsGnu'};
    my $linkSymlinks = $self->{'linkSymlinks'};
    my $lateCompress = $self->{'lateCompress'};
    my $lateLinks = $self->{'lateLinks'};
    my $suppressWarning = $self->{'suppressWarning'};

    # set save permissions
    umask(0077);

    my (%allBackupDirs) = ();
 
    my $lateLinkFile = "$targetDir/.storeBackupLinks/linkFile.bz2";
    my $wrLateLink;

    if ($lateLinks)
    {
	my $s = $lateCompress ?
	    "lateLinks and lateCompress are" : "lateLinks is";
	$prLog->print('-kind' => 'I',
		      '-str' => ["$s switched on"]);

	$wrLateLink = pipeToFork->new('-exec' => 'bzip2',
				      '-stdout' => $lateLinkFile,
				      '-outRandom' => "$tmpdir/stbuPipeTo12-",
				      '-delStdout' => 'no',
				      '-prLog' => $prLog);

	$wrLateLink->print("# link md5sum\n#\texistingFile\n#\tnewLink\n",
		   "# compress md5sum\n#\tfileToCompress\n# dir dirName\n",
		   "# symlink file\n#\ttarget\n",
		   "# linkSymlink link\n#\texistingFile\n#\tnewLink\n");
    }

    my $preservePerms = $self->{'preservePerms'};

    my $filesLeft = 1;
    my (%inProgress) = (); # $inProgress{$md5} = [[$dir, $file, $md5, $types],
                           #                      [$dir, $file, $md5, $types],
                           #                      [$dir, $file, $md5, $types]]
                           # Puffer für Dateien, die gerade komprimiert oder
                           # kopiert werden. $inProgress{$md5} = [] bedeutet,
                           # daß eine Datei mit der md5-Summe in Bearbeitung
                           # ist, aber keine gleichartigen in der Schlange sind
                           # -> Variable ist Merker + Puffer zugleich

    my $gnuCopy = 'cp';
    my (@gnuCopyParSpecial) = ('-a');

    my $blockParallel = 0;  # block* files are not read in parallel to others

    # main loop
    while ($filesLeft or
           $fifoCopy->getNoUsedEntries() > 0 or
           $fifoCompr->getNoUsedEntries() > 0 or
	   $fifoBlock->getNoUsedEntries() > 0 or
           $parForkCopy->getNoUsedEntries() > 0 or
           $parForkCompr->getNoUsedEntries() > 0 or
	   $parForkBlock->getNoUsedEntries() > 0)
    {
beginMainLoopNormalOperation:;

	# Warteschlangen füllen solange Platz ist und bis ein Fork
        # beendet ist oder ein neuer gestartet werden kann.
	while ($filesLeft and
               $fifoCopy->getNoFreeEntries() > 0 and
               $fifoCompr->getNoFreeEntries() > 0 and
	       $fifoBlock->getNoFreeEntries() > 0 and
               not $parForkCopy->jobFinished() and
               not $parForkCompr->jobFinished() and
	       not $parForkBlock->jobFinished() and
               not ($parForkCompr->getNoFreeEntries() > 0 and
                    $fifoCompr->getNoUsedEntries() > 0) and
               not ($parForkCopy->getNoFreeEntries() > 0 and
                    $fifoCopy->getNoUsedEntries() > 0) and
	       not ($parForkBlock->getNoFreeEntries() > 0 and
		    $fifoBlock->getNoUsedEntries() > 0))
        {
	    my ($dir, $file, $md5, $type);
	    my $n = ($dir, $file, $md5, $type) =
		$readDirAndCheck->next();

	    if ($n == 0)         # nix mehr zu holen!
	    {
		$filesLeft = 0;
		last;
	    }

#########!!!!!!!!
#if ($type eq 'repeat')
#{
#    print "got repeat $type <$dir>\n";
#}
#else
#{
#    my $m = ($md5 ? $md5 : "undef");
#    print "got fileDir $type $m <$dir> <$file>\n";
#}
	    last if ($type eq 'repeat'); # MD5Sum läuft noch

	    if ($file =~ /\n/ and
		not exists $$suppressWarning{'fileNameWithLineFeed'})
	    {
		my $f = $file;
		$f =~ s/\n/\\n/g;
		$prLog->print('-kind' => 'W',
			      '-str' => ["<$dir/$f> has \\n in the file name"])
	    }

            # Ok, wir haben was zu bearbeiten
            $main::tinyWaitScheduler->reset();

	    # Rechte etc. der Originaldatei lesen
	    my ($dev, $inode, $mode, $uid, $gid, $size, $atime,
		$mtime, $ctime);
	    my $_depth = -1;

	    if (not -l "$dir/$file" and not -e "$dir/$file")
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["<$dir/$file> removed during backup"]);
		next;
	    }

	    ($dev, $inode, $mode, $uid, $gid, $size, $atime,
	     $mtime, $ctime) =
		 (stat("$dir/$file"))[0,1,2,4,5,7,8,9,10];

	    if ($type eq 'd')
	    {
		my (@dummy);
		$_depth = (@dummy) = $file =~ m#/#g;
		if ($_depth + 1 <= $followLinks and
		    -l "$dir/$file")
		{
		    $_depth = 1;
		}
		else
		{
		    $_depth = -1;
		}
	    }
	    if ($_depth == -1)
	    {
		($dev, $inode, $mode, $uid, $gid, $size, $atime,
		 $mtime, $ctime) =
		     (lstat("$dir/$file"))[0,1,2,4,5,7,8,9,10];
	    }
            if (not defined $dev)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' => ["cannot stat <$file>: $!"]);
                next;
            }
            $mode &= 07777;

	    if ($file eq $aktInfoFile or $file eq "$aktInfoFile.bz2")
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot handle <$file>, " .
					 "collision with info file"]);
		next;
	    }

	    if ($type eq 'd')            # directory anlegen
	    {
		if ($lateLinks)
		{
		    my $lateDir = $file;
		    $lateDir =~ s/\n/\0/og;
		    $wrLateLink->print("dir $lateDir\n");
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["cannot create directory <$targetDir/$file>"],
				  '-exit' => 1)
			unless mkdir "$targetDir/$file", 0700;

		    if ($preservePerms)
		    {
			chown $uid, $gid, "$targetDir/$file";
			$setResetDirTimes->addDir($file, $atime, $mtime, $mode);
		    }
		    $prLog->print('-kind' => 'D',
				  '-str' =>
				  ["created directory <$targetDir/$file"])
			if ($debugMode > 0);
		}

		$main::stat->incr_noDirs($uid, $gid);

		$aktFilename->storeDir('-dir' => $file,
				       '-dev' => $dev,
				       '-inode' => $inode,
				       '-ctime' => $ctime,
				       '-mtime' => $mtime,
				       '-atime' => $atime,
				       '-uid' => $uid,
				       '-gid' => $gid,
				       '-mode' => $mode);
		next;
	    }

	    if ($type eq 'l')            # symbolic link
	    {
		my $l = readlink "$dir/$file";

		if ($linkSymlinks)
		{
		    if ($prevBackupOwnSeries and
			-l "$prevBackupOwnSeries/$file")
		    {
			my $l_prev = readlink "$prevBackupOwnSeries/$file";

			if ($l eq $l_prev)
			{
			    if ($lateLinks)
			    {
				my $_old = "$prevBackupOwnSeries/$file";
				$_old = ::relPath($targetDir, $_old);
				$_old =~ s/\n/\0/og;
				my $_new = $file;
				$_new =~ s/\n/\0/og;
				$wrLateLink->print(
				    "linkSymlink $l\n$_old\n$_new\n");
				&storeSymLinkInfos($uid, $gid, $targetDir,
						   $file, $dev, $inode,
						   $ctime, $mtime, $atime,
						   $aktFilename, $debugMode,
						   $prLog);
				next;
			    }
			    $prLog->print('-kind' => 'D',
					  '-str' =>
					  ["link $prevBackupOwnSeries/$file" .
					  "$targetDir/$file"])
				if $debugMode >= 2;
			    if (link "$prevBackupOwnSeries/$file",
				"$targetDir/$file")
			    {
				&changeSymlinkPerms($uid, $gid, $targetDir,
						    $file, $tmpdir, $prLog)
				    if ($preservePerms);
				&storeSymLinkInfos($uid, $gid, $targetDir,
						   $file, $dev, $inode,
						   $ctime, $mtime, $atime,
						   $aktFilename, $debugMode,
						   $prLog);
				next;

			    }
			}
		    }
		}
		if ($lateLinks)
		{
		    my $_file = "$file";
		    $_file =~ s/\n/\0/og;
		    my $_l = $l;
		    $l =~ s/\n/\0/og;
		    $wrLateLink->print("symlink $_file\n$l\n");
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot create symlink from " .
					     "<$targetDir/$file> -> $l"],
				  '-exit' => 1)
			unless symlink $l, "$targetDir/$file";

		    if ($preservePerms)
		    {
			&changeSymlinkPerms($uid, $gid, $targetDir,
			    $file, $tmpdir, $prLog);
		    }
		}

		&storeSymLinkInfos($uid, $gid, $targetDir, $file, $dev,
				   $inode, $ctime, $mtime, $atime,
				   $aktFilename, $debugMode, $prLog);
		next;
	    }

	    if ($type eq 'p')
	    {
		my ($ctime, $mtime, $atime) =
		    (stat("$dir/$file"))[10, 9, 8];

		&::makeFilePathCache("$targetDir/$file", $prLog) if $lateLinks;

		if ($specialTypeArchiver and $archiveTypes =~ /p/)
		{
		    &::createArchiveFromFile($file, $dir, $targetDir,
					     $specialTypeArchiver, $prLog,
					     $tmpdir);
		}
		else
		{
		    my $mknod = forkProc->new('-exec' => 'mknod',
					      '-param' => ["$targetDir/$file", 'p'],
					      '-outRandom' => "$tmpdir/mknod-",
					      '-prLog' => $prLog);
		    $mknod->wait();
		    my $out = $mknod->getSTDOUT();
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["STDOUT of <mknod $targetDir/$file p>:", @$out])
			if (@$out > 0);
		    $out = $mknod->getSTDERR();
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["STDERR of <mknod $targetDir/$dir p>:", @$out])
			if (@$out > 0);
		}

		if ($preservePerms)
		{
		    chown $uid, $gid, "$targetDir/$file";
		    chmod $mode, "$targetDir/$file";
		    utime $atime, $mtime, "$dir/$file" if $resetAtime;;
		    utime $atime, $mtime, "$targetDir/$file";
		}
		$main::stat->incr_noNamedPipes($uid, $gid);
		$prLog->print('-kind' => 'D',
			      '-str' =>
			      ["created named pipe <$targetDir/$file"])
		    if ($debugMode >= 2);
		$aktFilename->storeNamedPipe('-pipe' => $file,
					     '-dev' => $dev,
					     '-inode' => $inode,
					     '-ctime' => $ctime,
					     '-mtime' => $mtime,
					     '-atime' => $atime,
					     '-uid' => $uid,
					     '-gid' => $gid,
					     '-mode' => $mode);
		next;
	    }

	    if ($type eq 'S' or
                $type eq 'b' or
                $type eq 'c')
	    {
		&::makeFilePathCache("$targetDir/$file", $prLog) if $lateLinks;

		if ($specialTypeArchiver and $archiveTypes =~ /p/)
		{
		    &::createArchiveFromFile($file, $dir, $targetDir,
					     $specialTypeArchiver, $prLog,
					     $tmpdir);
		}
		else
		{
		    $gnucp or
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["no gnucp: internal error: " .
				       "cannot save file tyes Sbcp, " .
				      "set option cpIsGnu if gnucp is used"],
				      '-exit' => 1);

		    my $cp = forkProc->new('-exec' => $gnuCopy,
					   '-param' => [@gnuCopyParSpecial,
							"$dir/$file",
							"$targetDir/$file"],
					   '-outRandom' => "$tmpdir/gnucp-",
					   '-prLog' => $prLog);
		    $cp->wait();
		    my $out = $cp->getSTDOUT();
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["STDOUT of <$gnuCopy @gnuCopyParSpecial <$dir/$file> " .
				   "<$targetDir/$file>:", @$out])
			if (@$out > 0);
		    $out = $cp->getSTDERR();
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["STDERR of <$gnuCopy @gnuCopyParSpecial <$dir/$file>" .
				   "<$targetDir/$dir>:", @$out])
			if (@$out > 0);
		}

                if ($preservePerms)
		{
                    chown $uid, $gid, "$targetDir/$file";
                    chmod $mode, "$targetDir/$file";
                    utime $atime, $mtime, "$dir/$file" if $resetAtime;;
                    utime $atime, $mtime, "$targetDir/$file";
                }

		$main::stat->incr_noSockets($uid, $gid) if $type eq "S";
		$main::stat->incr_noBlockDev($uid, $gid) if $type eq "b";
		$main::stat->incr_noCharDev($uid, $gid) if $type eq "c";

		$prLog->print('-kind' => 'D',
			      '-str' =>
			      ["created special file ($type) <$targetDir/$file"])
		    if ($debugMode >= 2);

		$aktFilename->storeSpecial('-name' => $file,
                                           '-type' => $type,
                                           '-dev' => $dev,
                                           '-inode' => $inode,
                                           '-ctime' => $ctime,
                                           '-mtime' => $mtime,
                                           '-atime' => $atime,
                                           '-uid' => $uid,
                                           '-gid' => $gid,
                                           '-mode' => $mode);
		next;
	    }

	    if ($type eq 'bf')    # block file
	    {
#print "-0.1- blockFile: <$targetDir><$file> <$md5>\n";
		$main::stat->incr_noBlockedFiles();
		if (ref($md5) eq 'ARRAY')
		{
		    my ($ruleBS, $ruleCompress, $parallel, @ruleRead)
			= @$md5;
		    $blockParallel = $parallel;
		    $fifoBlock->add('-value' =>
				    ['file', $dir, $file, $uid, $gid,
				     $mode, $dev, $inode, $ctime, $mtime,
				     $atime, $size, $ruleBS, $ruleCompress,
				    \@ruleRead]);
		}
		else  # nothing has changed
		{
		    &::makeFilePathCache("$targetDir/$file", $prLog) if $lateLinks;

		    mkdir "$targetDir/$file", 0700 or
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["cannot mkdir <$targetDir/$file>"],
				      '-exit' => 1);
		    $main::stat->incr_noDirs($uid, $gid);

		    my ($x, $backupDir);
		    ($x, $x, $x, $backupDir, $x) =
			$oldFilename->getFilename($md5);

		    if ($lateLinks)
		    {
			my $from = "$backupDir/$file";
			my $to = "$targetDir/$file";
			unless (link "$from/$blockCheckSumFile.bz2",
				"$to/$blockCheckSumFile.bz2")
			{
			    $prLog->print('-kind' => 'E',
					  '-str' =>
					  ["cannot link/copy " .
					   "<$from/$blockCheckSumFile.bz2>".
					   " <$to/$blockCheckSumFile.bz2>"],
					  '-exit' => 1)
				unless (&::copyFile("$from/$blockCheckSumFile.bz2",
						    "$to/$blockCheckSumFile.bz2",
						    $prLog))

			}
			$from = ::relPath($targetDir, $from);
			$from =~ s/\n/\0/og;
			$to = ::relPath($targetDir, $to);
			$to =~ s/\n/\0/og;
			$wrLateLink->print("linkblock\n$from\n$to\n");
			$main::stat->incr_noLateLinks($uid, $gid);
		    }
		    else
		    {
#print "-0.2 hard link $backupDir/$file $targetDir/$file\n";
			&::hardLinkDir("$backupDir/$file",
				       "$targetDir/$file", '.*',
				       $uid, $gid, $mode, $prLog);
		    }
		    my $blockMD5File = "$targetDir/$file/$blockCheckSumFile.bz2";
		    my $block = pipeFromFork->new('-exec' => 'bzip2',
						  '-param' => ['-d'],
						  '-stdin' => $blockMD5File,
						  '-outRandom' =>
						  "$tmpdir/stbuPipeFrom11-",
						  '-prLog' => $prLog);
		    my $l;
		    while ($l = $block->read())
		    {
			chop $l;
			my ($blockMD5, $compr, $blockFilename)
			    = split(/\s/, $l, 3);
#print "blockMD5 = $blockMD5, compr = $compr, blockFilename = $blockFilename\n";
		    }
		    my $out = $block->getSTDERR();
		    if (@$out)
		    {
			$prLog->print('-kind' => 'E',
				      '-str' =>
				      ["reading from $blockMD5File generated",
				       @$out]);
			return 0;
		    }
		    $block->close();

		    if ($preservePerms)
		    {
			chown $uid, $gid, "$targetDir/$file";
			my $m = $mode;
			$m &= 0777;    # strip special permissions
			$m |= 0111;    # add directory permissions
			chmod $m, "$targetDir/$file";
			utime $atime, $mtime, "Dir/$file" if $resetAtime;;
			utime $atime, $mtime, "$targetDir/$file";
		    }

		    $aktFilename->store('-filename' => $file,# speichert in dbm
					'-md5sum' => $md5,   # .md5sum-Datei
					'-compr' => 'b',
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => 0,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => $size,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => $mode);
		}
		next;

	    }

	    #
	    # ($type eq 'f') -> normal file
	    #
	    $main::stat->addSumOrigFiles($size, $uid, $gid);

	    my ($comprOld, $linkFile, $newFile, $oldFile);
	    my ($inodeBackup, $backupDirIndex, $backupDir);
	    my $internalOld;
	    if ($type eq 'fnew')     # previous backup with this
	    {                        # file was done as blocked file,
		$linkFile = undef;   # so force compress or copy
	    }
	    else
	    {
		# jetzt in DBM-Files nachsehen und linken
		if ((($inodeBackup, $comprOld, $backupDirIndex,
		      $backupDir, $linkFile) =
		     $oldFilename->getFilename($md5)) == 5)
		{
#print "-0.8-<backupDir=$backupDir> <linkFile=$linkFile> <backupDirIndex=$backupDirIndex>\n";
		    if ($backupDirIndex != 1)  # identical file is in another series
		    {                          # --> recalc md5 sum
#print "-0.9-$main::sourceDir/$file-\n";
			$md5 = &::calcMD5("$main::sourceDir/$file", $prLog);
			$main::stat->add_noMD5edFiles(1);
			unless ($md5)
			{
			    $prLog->print('-kind' => 'W',
					  '-str' =>
			  ["file <$main::sourceDir/$file> deleted during backup (6)"])
				unless exists $$suppressWarning{'fileChange'};
			    next;
			}
		    }

		    $newFile = "$targetDir/$file";
		    $oldFile = "$backupDir/$linkFile";
		    $internalOld = ($backupDirIndex == 0) ?
			'internal' : 'old';
#print "-1- $newFile $oldFile\n";
#print "$targetDir($file) $backupDir($linkFile) $backupDirIndex\n";
		    my ($x, $oldSize);
		    if ($backupDirIndex == 0)  # first occurrence
		    {                          # in sourceDir
#print "1.2\n";
			if (-e "$main::sourceDir/$linkFile")
			{
			    $oldSize = (stat("$main::sourceDir/$linkFile"))[7];
#print "1.3\n";
			}
			else
			{
			    $oldSize = -1;
#print "1.4\n";
			}
		    }
#		    elsif ($backupDirIndex != 1)    # file found in other backup series
#		    {
#			$linkFile = undef;
#			$oldSize = -1;
#print "1.1\n";
#		    }
		    else
		    {
#print "1.5\n";
			($x, $x, $x, $oldSize, $x) =
			    $oldFilename->getInodebackupComprCtimeMtimeSizeMD5($linkFile);
		    }
		    if ($oldSize != $size and $oldSize > -1)
		    {
			my $comment = $comprOld eq 'u'? '' :
			    ' (with uncompressed files from backup)';
			$prLog->print('-kind' => 'W',
				      '-str' =>
				      ["possible hash collision between",
				      "<$oldFile> (size = $oldSize) and",
				      "<$newFile> (size = $size)",
				       "not linked, check md5 sums$comment"])
			    unless exists $$suppressWarning{'hashCollision'};
			$linkFile = undef;   # do not link
		    }
		}
		else             # Datei ist noch nicht bekannt
		{
		    $linkFile = undef;
		}
	    }

#print "------------- $dir/$file$postfix\n";
            if ($linkFile and
                $comprOld eq 'c' and
                -e "$dir/$file$postfix")
	    {
                $linkFile = undef;
#print "------------- found that file\n";
            }

#print "-2-\n";
	    if ($linkFile)
	    {
#print "-3-\n";
                # Alte Datei komprimiert
		if ($comprOld eq 'c')
		{
                    $newFile .= $postfix;
                    $oldFile .= $postfix;
		}

                $prLog->print('-kind' => 'D',
                              '-str' =>
                              ["link $oldFile $newFile"])
                    if ($debugMode >= 2);

                # Check existence, lateLinks not set and oldFile does not exist
                unless ($lateLinks or $oldFile)
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["(with old) cannot link (via md5) " .
				   "<$oldFile> <$newFile>"])
			if ($debugMode >= 1);
		    $linkFile = undef;
		    $oldFilename->deleteEntry($md5,    # in Zukunft nicht mehr
					      $file);  # mit dieser Datei linken
                }

                # In Datei schreiben
                if ($lateLinks)
		{
		    ++$allBackupDirs{$backupDir}
		        if $backupDir ne $targetDir;
		    my $existingFile = ::relPath($targetDir, $oldFile);
		    my $newLink = ::relPath($targetDir, $newFile);

		    $existingFile =~ s/\n/\0/og;
		    $newLink =~ s/\n/\0/og;
		    $wrLateLink->print("link $md5\n$existingFile\n$newLink\n");

		    $main::stat->incr_noLateLinks($uid, $gid);

                    # Schreiben der Informationen
                    $aktFilename->store('-filename' => $file,
                                        '-md5sum' => $md5,
					'-compr' => $comprOld,
					'-dev' => $dev,
					'-inode' => $inode,
					'-inodeBackup' => $inodeBackup,
					'-ctime' => $ctime,
					'-mtime' => $mtime,
					'-atime' => $atime,
					'-size' => $size,
					'-uid' => $uid,
					'-gid' => $gid,
					'-mode' => $mode,
					'-storeInDBM' => 0  # in dbm sinnlos
                                       );
                }
		else  # Oder direkt linken
		{
		    if (link $oldFile, $newFile)
		    {
			if ($preservePerms)
			{
			    chown $uid, $gid, $newFile;
			    chmod $mode, $newFile;
			}

			# Schreiben der Informationen
			$aktFilename->store('-filename' => $file,
					    '-md5sum' => $md5,
					    '-compr' => $comprOld,
					    '-dev' => $dev,
					    '-inode' => $inode,
					    '-inodeBackup' => $inodeBackup,
					    '-ctime' => $ctime,
					    '-mtime' => $mtime,
					    '-atime' => $atime,
					    '-size' => $size,
					    '-uid' => $uid,
					    '-gid' => $gid,
					    '-mode' => $mode,
					    '-storeInDBM' => 0  # in dbm sinnlos
			    );
			if ($comprOld eq 'u')
			{
			    $main::stat->addSumUnchangedCopy($size);
			}
			else   # $comprOld eq 'c'
			{
			    $main::stat->addSumUnchangedCompr($size);
			}
		    }
		    else
		    {
			$prLog->print('-kind' => 'W',
				      '-str' =>
				      ["(with old) cannot link (via md5) " .
				       "<$oldFile> <$newFile>"])
			    if ($debugMode >= 1);
			$linkFile = undef;         # => kopieren oder komprimieren
			$oldFilename->deleteEntry($md5,    # in Zukunft nicht mehr
						  $file);  # mit dieser Datei linken
		    }
		}

                # Stats nur wenn wirklich gelinkt
                if (defined $linkFile)
		{
                    if ($comprOld eq 'u')
		    {
                        if ($internalOld eq 'internal')
			{
                            $main::stat->addSumLinkedInternalCopy($size);
                        }
                        else
			{
                            $main::stat->addSumLinkedOldCopy($size);
                        }
                    }
                    else
		    {
                        if ($internalOld eq 'internal')
			{
                            $main::stat->addSumLinkedInternalCompr($size);
                        }
                        else
			{
                            $main::stat->addSumLinkedOldCompr($size);
                        }
                    }
                }
	    }

            # existiert noch nicht, copy oder compress
#print "- 4 -\n";
	    if (not defined $linkFile)
	    {
		&::makeFilePathCache("$targetDir/$file", $prLog) if $lateLinks;

#print "- 5 -\n";
		if (exists $inProgress{$md5}) # Auf Kompression/Kopie warten
		{
#print "- 6 -\n";
		    push @{$inProgress{$md5}}, [$dir, $file, $md5, 'f'];
		    $prLog->print('-kind' => 'D',
				  '-str' => ["found identical file <$file>"])
			if $debugMode >= 3;
		    next;
		}

                $inProgress{$md5} = [];   # merken, wird kopiert/komprimiert

#print "- 7 -\n";
		no warnings 'newline';
		if (($comprRule->hasLine() == 1 and
		     $comprRule->checkRule($file, $size, $mode, $ctime, $mtime,
					      $uid, $gid, $type) == 1)
		    or -e "$dir/$file$postfix") # Datei hat nicht .bz2, es
		{                               # existiert aber Datei mit .bz2
		    if (-e "$dir/$file$postfix")
		    {
#print "- 8 -\n";
			$fifoCopy->add('-value' =>
				       [$dir, $file, $uid, $gid, $mode,
					$md5, 'copy']);
		    }
		    elsif ($lateCompress)
		    {
#print "- 9 -\n";
			$fifoCopy->add('-value' =>
				       [$dir, $file, $uid, $gid, $mode,
					$md5, 'compr']);
		    }
		    else   # compress file
		    {
#print "- 10 -\n";
			$fifoCompr->add('-value' =>
					[$dir, $file, $uid, $gid, $mode,
					 $md5, 'compr']);
		    }
		}
		else       # copy file
		{
#print "- 11 -\n";
		    $fifoCopy->add('-value' =>
				   [$dir, $file, $uid, $gid, $mode,
				    $md5, 'copy']);
                }
	    }
	} # Ende Schleife Warteschlagen füllen

        # Alte Kopier-Jobs abholen
        foreach my $i ($parForkCopy->checkAll())
        {
            # We did something
            $main::tinyWaitScheduler->reset();

            my $stderr = $i->getSTDERR();
            my ($dev, $inode, $dir, $file, $uid, $gid, $mode, $md5,
                $ctime, $mtime, $atime, $size, $compr, $tmpMD5File) =
                    @{$i->get('-what' => 'info')};

	    if (&::waitForFile("$targetDir/$file"))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["<$targetDir/$file> was not created (1)"]);
		next;
	    }
            if ($preservePerms and not $lateLinks)
	    {
                chown $uid, $gid, "$targetDir/$file";
                chmod $mode, "$targetDir/$file";
                utime $atime, $mtime, "$dir/$file" if $resetAtime;
                utime $atime, $mtime, "$targetDir/$file";
            }

            my $inodeBackup = (stat("$targetDir/$file"))[1];
	    $inodeBackup = 0 unless $inodeBackup;   # if timing issue,
	                                            # value is not used at all

            if (@$stderr > 0)
            {
		unless (-e "$dir/$file") # file was deleted during copying
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["file <$dir/$file> deleted during backup (2)"]);
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["copying <$dir/$file> -> <$targetDir/$file>" .
				   " generated the following error messages:",
				   @$stderr]);
		}
		unlink "$targetDir/$file";
                next;
            }

	    local *TMPMD5;
	    unless (&::waitForFile($tmpMD5File) == 0 and
		open(TMPMD5, $tmpMD5File))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot read recalced md5sum " .
					 "of <$targetDir/$file>" .
					 "; file is not backed up (1)"]);
		next;
	    }
	    my $lastMD5 = <TMPMD5>;
	    chomp $lastMD5;
	    my $lastSize = <TMPMD5>;
	    chomp $lastSize;
	    close(TMPMD5);
	    unlink $tmpMD5File;

	    $main::stat->add_noMD5edFiles(1);
	    unless ($lastMD5)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["file <$dir/$file> deleted during backup (3)"])
		    unless exists $$suppressWarning{'fileChange'};
		next;
	    }
	    if ($lastMD5 ne $md5 or $lastSize != $size)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["file <$dir/$file> changed during backup"])
		    unless exists $$suppressWarning{'fileChange'};
		$md5 = $lastMD5;
		$size = $lastSize;
	    }

            $prLog->print('-kind' => 'D',
                          '-str' =>
                          ["finished copy <$dir/$file> " .
                           "<$targetDir/$file>"])
                if ($debugMode >= 2);

            $main::stat->incr_noForksCP();
            $main::stat->addSumNewCopy($size);

            $aktFilename->store('-filename' => $file,  # speichert in dbm
                                '-md5sum' => $md5,     # .md5sum-Datei
                                '-compr' => $compr,
                                '-dev' => $dev,
                                '-inode' => $inode,
                                '-inodeBackup' => $inodeBackup,
                                '-ctime' => $ctime,
                                '-mtime' => $mtime,
                                '-atime' => $atime,
                                '-size' => $size,
                                '-uid' => $uid,
                                '-gid' => $gid,
                                '-mode' => $mode);


            if (exists $inProgress{$md5} and
                @{$inProgress{$md5}} > 0)  # gepufferte Files mit
            {                              # gleicher md5 Summe bearbeiten
                $filesLeft = 1;
                $readDirAndCheck->pushback($inProgress{$md5}, $prLog,
		    $debugMode >= 3 ? 1 : 0);
            }
            delete $inProgress{$md5};
        }

	# neue Block-md5 Jobs einhägen
	while ($parForkBlock->getNoFreeEntries() > 0 and
	       $fifoBlock->getNoUsedEntries() > 0)
	{
            # We did something
            $main::tinyWaitScheduler->reset();

	    my ($devfile, @param) = @{$fifoBlock->get()};

	    # alle md5 Summen berechnen,
#print "-11- checkBlock, fifoBlock->get: $devfile\n";
	    my $tmpName = &::uniqFileName("$tmpdir/storeBackup-block.");
#print "-12-\n";
	    if ($devfile eq 'file')
	    {
		my ($dir, $file, $uid, $gid, $mode, $dev,
		    $inode, $ctime, $mtime, $atime, $size, $checkBlocksBS,
		    $compressBlock, $blockRead) = (@param);

		unless ($lateLinks)
		{
		    mkdir "$targetDir/$file" or
			$prLog->print('-kind' => 'E',
				      '-str' => ["cannot mkdir <$targetDir/$file>"],
				      '-exit' => 1);
		    chown $uid, $gid, "$targetDir/$file";
		}
		$parForkBlock->add_noblock('-function' => \&::calcBlockMD5Sums,
					   '-funcPar' => ["$dir/$file", $targetDir,
							  $file, $checkBlocksBS,
							  $compressBlock,
							  $blockRead,
							  $compressCommand,
							  $compressOptions,
							  $postfix,
							  $oldFilename, $lateLinks,
							  $lateCompress,
							  $noCompress, $prLog,
							  $tmpName,
							  $blockCheckSumFile,
							  $ctime, $mtime],
					   '-info' => [$dev, $inode, $dir,
						       $file, $uid, $gid,
						       $mode,
						       $ctime, $mtime,
						       $atime, $size,
						       $compressBlock,
						       $tmpName]);

		$prLog->print('-kind' => 'I',
			      '-str' => ["saving blocked file <$file> (" .
			      (&::humanReadable($size))[0] . ')']);
	    }
	    elsif ($devfile eq 'device')
	    {
		my ($device, $relDir, $blockSize, $compressBlock, $parallel)
		    = (@param);
		$blockParallel = $parallel;
		my $relDir2 = $device;
		$relDir2 =~ s/\//_/g;
		$relDir2 =~ s/\A_*(.*)_*\Z/$1/;
		&::makeDirPathCache("$targetDir/$relDir/$relDir2", $prLog);
		$parForkBlock->add_noblock('-function' => \&::calcBlockMD5Sums,
					   '-funcPar' => [$device, $targetDir,
							  "$relDir/$relDir2",
							  $blockSize,
							  $compressBlock,
							  ['dd', "bs=$blockSize"],
							  $compressCommand,
							  $compressOptions,
							  $postfix,
							  $oldFilename, $lateLinks,
							  $lateCompress,
							  $noCompress, $prLog,
							  $tmpName,
							  $blockCheckSumFile,
							  0, 0],
					   '-info' => ['DEVICE', 0, $device,
						       "$relDir/$relDir2",
						       0, 0,
						       0600,
						       0, 0,
						       0, 0,
						       $compressBlock,
						       $tmpName]);
		$prLog->print('-kind' => 'I',
			      '-str' => ["saving device <$device> to " .
					 "$targetDir/$relDir/$relDir2"]);
	    }
	    else
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["assertion <$devfile> @param"],
			      '-exit' => 1);
	    }
#print "-13-\n";
	}
#print "-14-\n";

        # neue Kopier-Jobs einhängen
        while ($parForkCopy->getNoFreeEntries() > 0 and
               $fifoCopy->getNoUsedEntries() > 0)
        {
            # We did something
            $main::tinyWaitScheduler->reset();

            my ($dir, $file, $uid, $gid, $mode, $md5, $copyCompr) =
                @{$fifoCopy->get()};    # copyCompr is for lateCompression
	    unless (-e "$dir/$file")    # file was deleted during wait in queue
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["file <$dir/$file> deleted during backup (4)"]);
		next;
	    }
#print "-15-$file\n";
            my ($dev, $inode, $ctime, $mtime, $atime, $size) =
                (lstat("$dir/$file"))[0, 1, 10, 9, 8, 7];
            $mode &= 07777;

	    my $compr = 'u';
#print "copyCompr = <$copyCompr>\n";
	    if ($copyCompr eq 'compr')
	    {
#print "-16-\n";
		$compr = 'c';
		# 'compress' refers to entry in .md5CheckSums.info
		my $existingFile = $file;
		$existingFile =~ s/\n/\0/og;
		$wrLateLink->print("compress $md5\n$existingFile\n");
	    }

            if ($size <= $main::minCopyWithFork) # direkt kopieren (ohne fork)
            {
#print "-17-\n";
                $prLog->print('-kind' => 'D',
                              '-str' => ["copy $dir/$file $targetDir/$file"])
                    if ($debugMode >= 2);

                unless (&::copyFile("$dir/$file", "$targetDir/$file", $prLog))
                {
                    $prLog->print('-kind' => 'E',
                                  '-str' => ["could not copy $dir/$file " .
					     "$targetDir/$file"]);
                    next;
                }

		my $lastMD5 = &::calcMD5("$dir/$file");
		if ($debugMode >= 3)
		{
		    $prLog->print('-kind' => 'D',
				  '-str' => ["md5sum (recalc) $dir/$file"]);
		}
		$main::stat->add_noMD5edFiles(1);
		unless ($lastMD5)
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["file <$dir/$file> deleted during backup (5)"])
			unless exists $$suppressWarning{'fileChange'};

		    next;
		}
		if ($lastMD5 ne $md5)
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["file <$dir/$file> changed during backup"])
			unless exists $$suppressWarning{'fileChange'};

		    $md5 = 'g' x 32;
		}

                if ($preservePerms and not $lateLinks)
		{
                    chown $uid, $gid, "$targetDir/$file";
                    chmod $mode, "$targetDir/$file";
                    utime $atime, $mtime, "$dir/$file" if $resetAtime;
                    utime $atime, $mtime, "$targetDir/$file";
                }

                my $inodeBackup = (stat("$targetDir/$file"))[1];
		$inodeBackup = 0 unless $inodeBackup;   # if timing issue,
	                                            # value is not used at all

                $aktFilename->store('-filename' => $file,  # speichert in dbm
                                    '-md5sum' => $md5,     # .md5sum-Datei
                                    '-compr' => $compr,
                                    '-dev' => $dev,
                                    '-inode' => $inode,
                                    '-inodeBackup' => $inodeBackup,
                                    '-ctime' => $ctime,
                                    '-mtime' => $mtime,
                                    '-atime' => $atime,
                                    '-size' => $size,
                                    '-uid' => $uid,
                                    '-gid' => $gid,
                                    '-mode' => $mode);

                $main::stat->addSumNewCopy($size);

                if (exists $inProgress{$md5} and
                    @{$inProgress{$md5}} > 0)  # gepufferte Files mit
                {                              # gleicher md5 Summe bearbeiten
                    $filesLeft = 1;
                    $readDirAndCheck->pushback($inProgress{$md5}, $prLog,
			$debugMode >= 3 ? 1 : 0);
                }
                delete $inProgress{$md5};
            }
            else                         # mit fork/cp,rsync kopieren
            {
                $prLog->print('-kind' => 'D',
                              '-str' =>
                              ["copy $dir/$file $targetDir/$file"])
                    if ($debugMode >= 2);

		my $tmpMD5File = &::uniqFileName("$tmpdir/storeBackup-md5.");
		$parForkCopy->add_noblock('-exec' => $main::stbuMd5cp,
					  '-param' =>
					  ["$dir/$file",
					  "$targetDir/$file", $tmpMD5File],
                                          '-workingDir' => '.',
                                          '-outRandom' => "$tmpdir/stderr",
                                          '-info' =>
                                          [$dev, $inode, $dir, $file, $uid,
                                           $gid, $mode, $md5, $ctime, $mtime,
                                           $atime, $size, $compr, $tmpMD5File])
		    or die "Must not happen (copy)";
            }
        }
#print "-18-\n";

        # Komprimier Jobs abholen
        foreach my $i ($parForkCompr->checkAll())
        {
#print "-19-\n";
            # We did something
            $main::tinyWaitScheduler->reset();

            my $stderr = $i->getSTDERR();
            my ($dev, $inode, $dir, $file, $uid, $gid, $mode, $md5,
		$ctime, $mtime, $atime, $size, $tmpMD5File) =
		    @{$i->get('-what' => 'info')};

	    if (&::waitForFile("$targetDir/$file$postfix"))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["<$targetDir/$file$postfix> " .
					 "was not created (2)"]);
		next;
	    }

            if ($preservePerms and not $lateLinks)
	    {
                chown $uid, $gid, "$targetDir/$file$postfix";
                chmod $mode, "$targetDir/$file$postfix";
                utime $atime, $mtime, "$dir/$file" if $resetAtime;
                utime $atime, $mtime, "$targetDir/$file$postfix";
            }
            my $inodeBackup = (stat("$targetDir/$file$postfix"))[1];
	    $inodeBackup = 0 unless $inodeBackup;   # if timing issue,
	                                            # value is not used at all

            if (@$stderr > 0)
            {
		unless (-e "$dir/$file") # file was deleted during compression
		{
		    $prLog->print('-kind' => 'W',
				  '-str' =>
				  ["file <$dir/$file> deleted during backup (6)"]);
		}
		else
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["compressing <$dir/$file> -> " .
				   "<$targetDir/$file$postfix>" .
				   " generated the following error messages:",
				   @$stderr]);
		}
		unlink "$targetDir/$file$postfix";
                next;
            }

	    local *TMPMD5;
	    unless (&::waitForFile($tmpMD5File) == 0 and
		open(TMPMD5, $tmpMD5File))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot read recalced md5sum " .
					 "of <$targetDir/$file>" .
			      "; file is not backed up (2)"]);
		unlink $tmpMD5File;
		next;
	    }
#	    unless (&::waitForFile($tmpMD5File) or
#		    open(TMPMD5, $tmpMD5File))
#	    {
#		$prLog->print('-kind' => 'E',
#			      '-str' => ["cannot read recalced md5sum " .
#					 "of <$targetDir/$file>" .
#			      "; file is not backed up"]);
#		next;
#	    }
	    my $lastMD5 = <TMPMD5>;
	    my $lastSize = <TMPMD5>;
	    close(TMPMD5);
	    if ((not defined $lastMD5) or (not defined $lastSize))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot read recalced md5sum " .
					 "of <$targetDir/$file>" .
			      "; file is not backed up (3)"]);
		unlink $tmpMD5File;
		next;
	    }
	    unlink $tmpMD5File;
	    chomp $lastMD5;
	    chomp $lastSize;

	    $main::stat->add_noMD5edFiles(1);
	    unless ($lastMD5)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["file <$dir/$file> deleted during backup (7)"])
		    unless exists $$suppressWarning{'fileChange'};
		next;
	    }
	    if ($lastMD5 ne $md5 or $lastSize != $size)
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["file <$dir/$file> changed during backup"])
		    unless exists $$suppressWarning{'fileChange'};
		$md5 = $lastMD5;
		$size = $lastSize;
	    }

            $prLog->print('-kind' => 'D',
                          '-str' =>
                          ["finished $compress <$dir/$file> " .
                           "<$targetDir/$file$postfix>"])
                if ($debugMode >= 2);

            $main::stat->incr_noForksCompress();
	    my $comprSize = (stat("$targetDir/$file$postfix"))[7];
            $main::stat->addSumNewCompr($comprSize, $size);

#print "- 22 - file = <$file>\n";
            $aktFilename->store('-filename' => $file,  # speichert in dbm
                                '-md5sum' => $md5,     # .md5sum-Datei
                                '-compr' => 'c',
                                '-dev' => $dev,
                                '-inode' => $inode,
                                '-inodeBackup' => $inodeBackup,
                                '-ctime' => $ctime,
                                '-mtime' => $mtime,
                                '-mtime' => $mtime,
                                '-atime' => $atime,
                                '-size' => $size,
                                '-uid' => $uid,
                                '-gid' => $gid,
                                '-mode' => $mode);

            if (exists $inProgress{$md5} and
                @{$inProgress{$md5}} > 0)  # gepufferte Files mit
            {                              # gleicher md5 Summe bearbeiten
                $filesLeft = 1;
                $readDirAndCheck->pushback($inProgress{$md5}, $prLog,
		    $debugMode >= 3 ? 1 : 0);
            }
            delete $inProgress{$md5};
        }
#print "-23-\n";

        # Block-md5 Jobs abholen
	while (1)
        {
	    my $i;
	    if ($blockParallel)
	    {
		$i = $parForkBlock->checkOne();
	    }
	    else
	    {
		$i = $parForkBlock->waitForAllJobs();
	    }
	    last unless $i;

            # We did something
	    $main::tinyWaitScheduler->reset();

	    my ($dev, $inode, $dir, $file, $uid, $gid,
		$mode, $ctime, $mtime, $atime, $size, $compressBlock,
		$tmpName) =
		    @{$i->get('-what' => 'info')};
	    chown $uid, $gid, $file;
	    $setResetDirTimes->addDir($file, $atime, $mtime,
				      (($mode & 0777) | 0111));

	    unless (-r $tmpName)
	    {
		# message is important to increment ERROR counter in prLog
		# Error message in calcBlockMD5Sums is called in fork!
		$prLog->print('-kind' => 'E',
			      '-str' => ["skipping blocked file"]);
		next;
	    }

	    local *BLOCK;
	    unless (&::waitForFile($tmpName) == 0 and
		    open(BLOCK, "< $tmpName"))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot open <$tmpName>"],
			      '-add' => [__FILE__, __LINE__],
			      '-exit' => 1);
	    }
	    my ($statSourceSize, $statStbuSize, $statNoForksCP, $statNoForksCompress,
		$statNoBlocks, $statNoLateLinks, $allMD5, $blockMD5,
		$blockFilename, $l, $noWarnings, $noErrors,
		$noBlockComprCheckCompr, $noBlockComprCheckCp);

	    while ($l = <BLOCK>)
	    {
		chop $l;
		my $first;
		($first, $l) = split(/\s/, $l, 2);
		if ($first eq 'allMD5')
		{
		    ($allMD5, $statSourceSize, $statStbuSize, $statNoForksCP,
		     $statNoForksCompress, $statNoBlocks, $statNoLateLinks,
		     $noWarnings, $noErrors, $noBlockComprCheckCompr,
		     $noBlockComprCheckCp) =
			 split(/\s/, $l);
#print "setting allMD5\n";
		}
		elsif ($first eq 'link')
		{
		    $wrLateLink->print("$first $l\n");     # 'link md5'
		    my $existingFile = <BLOCK>;
		    chop $existingFile;
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["file <$tmpName> ends unexpected at line $."],
				  '-exit' => 1)
			unless $existingFile;
		    $existingFile = ::relPath($targetDir, $existingFile);
		    $existingFile =~ s/\n/\0/og;
		    $wrLateLink->print("$existingFile\n");
		    my $newLink = <BLOCK>;
		    chop $newLink;
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["file <$tmpName> ends unexpected at line $."],
				  '-exit' => 1)
			unless $newLink;
		    $newLink = ::relPath($targetDir, $newLink);
		    $newLink =~ s/\n/\0/og;
		    $wrLateLink->print("$newLink\n");
#print "blocklatelinks: $first $l, $existingFile -> $newLink\n";
		}
		elsif ($first eq 'compress')
		{
		    $wrLateLink->print("$first $l\n");   # 'compress md5'
		    my $existingFile = <BLOCK>;
		    chop $existingFile;
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["file <$tmpName> ends unexpected at line $."],
				  '-exit' => 1)
			unless $existingFile;
		    $existingFile = ::relPath($targetDir, $existingFile);
		    $existingFile =~ s/\n/\0/og;
		    $wrLateLink->print("$existingFile\n");
		}
		else
		{
		    my $compr;
		    ($blockMD5, $compr, $blockFilename) =
			($first, split(/\s/, $l, 2));
		    $oldFilename->setBlockFilenameCompr($blockMD5,
						   "$targetDir/$blockFilename",
							$compr);
#print "blockMD5 = $blockMD5, blockFilename = $blockFilename\n";
		    chmod $mode, "$targetDir/$blockFilename";
		    chown $uid, $gid, "$targetDir/$blockFilename";
		}
	    }
#print "allMD5 = $allMD5, statSourceSize = $statSourceSize, statStbuSize = $statStbuSize\n" .
#    "statNoForksCP = $statNoForksCP, statNoForksCompress = $statNoForksCompress\n" .
#    "statNoBlocks = $statNoBlocks, statNoLateLinks = $statNoLateLinks\n" .
#    "noWarnings = $noWarnings, noErrors = $noErrors\n" .
#    "noBlockComprCheckCompr = $noBlockComprCheckCompr, noBlockComprCheckCp = $noBlockComprCheckCp\n";
	    close(BLOCK);
	    unlink $tmpName;

	    $main::stat->addSumOrigFiles($statSourceSize, $uid, $gid);
	    $main::stat->addSumMD5Sum($statSourceSize);
	    $main::stat->incr_noLateLinks($uid, $gid, $statNoLateLinks);
	    $main::stat->incr_noForksCP($statNoForksCP);
	    $main::stat->incr_noForksCompress($statNoForksCompress);
	    $main::stat->addSumBlockComprCheckCompr($noBlockComprCheckCompr);
	    $main::stat->addSumBlockComprCheckCp($noBlockComprCheckCp);
	    $prLog->addEncounter('-kind' => 'E',
				 '-add' => $noErrors);
	    $prLog->addEncounter('-kind' => 'W',
				 '-add' => $noWarnings);

	    if ($compressBlock eq 'u' or $lateCompress)
	    {
		$main::stat->addSumNewCopy($statStbuSize);
	    }
	    else
	    {
		$main::stat->addSumNewCompr($statStbuSize, $statSourceSize);
	    }
	    $main::stat->add_noMD5edFiles($statNoBlocks + 1);
	    $main::stat->incr_noForksMD5();

	    $aktFilename->store('-filename' => $file,  # speichert in dbm
				'-md5sum' => $allMD5,  # .md5sum-Datei
				'-compr' => 'b',
				'-dev' => $dev,
				'-inode' => $inode,
				'-inodeBackup' => 0,
				'-ctime' => $ctime,
				'-mtime' => $mtime,
				'-mtime' => $mtime,
				'-atime' => $atime,
				'-size' => $size,
				'-uid' => $uid,
				'-gid' => $gid,
				'-mode' => $mode);
	}
#print "-25-\n";
        # neue Komprimier-Jobs einhängen
        while ($parForkCompr->getNoFreeEntries() > 0 and
               $fifoCompr->getNoUsedEntries() > 0)
        {
            # We did something
            $main::tinyWaitScheduler->reset();

            my ($dir, $file, $uid, $gid, $mode, $md5) =
                @{$fifoCompr->get()};
	    unless (-e "$dir/$file")    # file was deleted during wait in queue
	    {
		$prLog->print('-kind' => 'W',
			      '-str' =>
			      ["file <$dir/$file> deleted during backup (8)"]);
		next;
	    }
            my ($dev, $inode, $ctime, $mtime, $atime, $size) =
                (stat("$dir/$file"))[0, 1, 10, 9, 8, 7];
            $mode &= 07777;

            $prLog->print('-kind' => 'D',
                          '-str' => ["$compress < $dir/$file > " .
                                     "$targetDir/$file$postfix"])
                if ($debugMode >= 2);

	    my $tmpMD5File = &::uniqFileName("$tmpdir/storeBackup-md5.");
	    $parForkCompr->add_noblock('-exec' => $main::stbuMd5Exec,
                               '-param' => [$compressCommand, "$dir/$file",
			       "$targetDir/$file$postfix",
			       $tmpMD5File, $tmpdir,
			       @$compressOptions],
                               '-workingDir' => '.',
                               '-outRandom' => "$tmpdir/stderr",
                               '-info' =>
                               [$dev, $inode, $dir, $file, $uid, $gid,
                                $mode, $md5, $ctime, $mtime,
                                $atime, $size, $tmpMD5File])
		or die "must not happen (compr)";


        }

        $main::stat->checkPrintTimeProgressReport();
        # Wait in case we did nothing in this loop run
        $main::tinyWaitScheduler->wait();
    }
#print "-26-\n";

    if (%inProgress)
    {
	my $md5;
	$prLog->print('-kind' => 'D',
		      '-str' => ["repeat checking of identical files"])
	    if $debugMode >= 3;
	foreach $md5 (keys %inProgress)
	{
	    $readDirAndCheck->pushback($inProgress{$md5}, $prLog,
		$debugMode >= 3 ? 1 : 0);
	}
	(%inProgress) = ();
	no warnings 'deprecated';
	goto beginMainLoopNormalOperation;
    }
    $main::stat->printProgressReport();

#print "-27-\n";
    if ($lateLinks)
    {
#print "-28-\n";
	$wrLateLink->wait();
#print "-29-\n";
	my $out = $wrLateLink->getSTDERR();
	if (@$out)
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["writing lateLinks file reports errors:",
				     @$out]);
	    exit 1;
	}
	$wrLateLink->close();

#print "-30-\n";
	if (scalar(%allBackupDirs))
	{
#print "-31-\n";
	    # generate information that references have to be resolved
	    my $to = "$targetDir/.storeBackupLinks/linkTo";
	    local *TO;
	    open(TO, ">", $to) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot open <$to>"],
			      '-add' => [__FILE__, __LINE__],
			      '-exit' => 1);

	    my $abd;
	    foreach $abd (%allBackupDirs)
	    {
#print "-32-$abd-\n";
		my $relpath = ::relPath($targetDir, $abd);
		next if $relpath eq '.';
		if (!print TO "$relpath\n")
		{
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot write to <$to>"],
				  '-exit' => 1);
		    next;
		}
		my $i = 0;
		local *FROM;
		my $from = "$abd/.storeBackupLinks/linkFrom";
		$i++ while -e "$from$i";
		open(FROM, ">", "$from$i") or
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot write to <$from$i>"],
				  '-exit' => 1);
		$relpath = ::relPath($abd, $targetDir);
		next if $relpath eq '.';
		print FROM "$relpath\n" or
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot write to <$from$i>"],
				  '-exit' => 1);
		close(FROM) or
		    $prLog->print('-kind' => 'E',
				  '-str' => ["cannot close <$from$i>"],
				  '-exit' => 1);
	    }
	    close(TO) or
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot close <$to>"],
			      '-exit' => 1);
	}
    }
#print "-33-\n";
}


########################################
# helper subroutines in package scheduler
sub changeSymlinkPerms
{
    my ($uid, $gid, $targetDir, $file, $tmpdir, $prLog) = (@_);
    # Some OS (eg. Linux) do not change the symlink itself
    # when calling the system call chmod. They change the ownership
    # of the file referred to by the sympolic link.
    # Therefore, lchown has to be used
    my $chown =
	forkProc->new('-exec' => 'chown',
		      '-param' => ['-h', "$uid:$gid",
				   "$targetDir/$file"],
		      '-outRandom' => "$tmpdir/chown-",
		      '-prLog' => $prLog);
    $chown->wait();

#			utime $atime, $mtime, "$dir/$file" if $resetAtime;
#			utime $atime, $mtime, "$targetDir/$file";
#			^^ utime changes original file!
}

##############################
sub storeSymLinkInfos
{
    my ($uid, $gid, $targetDir, $file, $dev, $inode, $ctime, $mtime,
	$atime, $aktFilename, $debugMode, $prLog) = (@_);

    $main::stat->incr_noSymLinks($uid, $gid);
    $prLog->print('-kind' => 'D',
		  '-str' =>
		  ["created symbolic link <$targetDir/$file"])
	if ($debugMode >= 2);

    $aktFilename->storeSymlink('-symlink' => $file,
			       '-dev' => $dev,
			       '-inode' => $inode,
			       '-ctime' => $ctime,
			       '-mtime' => $mtime,
			       '-atime' => $atime,
			       '-uid' => $uid,
			       '-gid' => $gid);
}


##################################################
package Statistic;
our @ISA = qw( statisticDeleteOldBackupDirs );

########################################
sub new
{
    my $class = shift;

    my (%params) = ('-startDate'         => undef,
		    '-aktDate'           => undef,
		    '-userGroupStatFile' => undef,     # Flag
		    '-exceptSuffix'      => undef,     # Filename (if set)
		    '-prLog'             => undef,
		    '-progressReport'    => undef,
		    '-progressDeltaTime' => 0,
		    '-withUserGroupStat' => undef,
		    '-userGroupStatFile' => undef,
		    '-compress'          => undef
		    );

    &::checkObjectParams(\%params, \@_, 'Statistic::new',
			 ['-prLog', '-progressReport',
			  '-withUserGroupStat', '-userGroupStatFile',
			  '-compress']);
    my $self =
	statisticDeleteOldBackupDirs->new('-prLog' => $params{'-prLog'},
					  '-kind' => 'S');

    &::setParamsDirect($self, \%params);

    $self->{'userGroupFlag'} = ($self->{'withUserGroupStat'} or
				$self->{'userGroupStatFile'}) ? 1 : undef;

    if ($self->{'userGroupFlag'})
    {
	my (%uidStatInodes) = ();
	my (%uidStatSize) = ();
	my (%gidStatInodes) = ();
	my (%gidStatSize) = ();
	$self->{'uidStatInodes'} = \%uidStatInodes;
	$self->{'uidStatSize'} = \%uidStatSize;
	$self->{'gidStatInodes'} = \%gidStatInodes;
	$self->{'gidStatSize'} = \%gidStatSize;
    }

    my (%uidSource) = ();       # Hash mit key = uid, value = size
    my (%gidSource) = ();       # Hash mit key = gid, value = size
    my (%uidBackup) = ();       # Hash mit key = uid, value = size
    my (%gidBackup) = ();       # Hash mit key = gid, value = size
    $self->{'uidSource'} = \%uidSource;
    $self->{'gidSource'} = \%gidSource;
    $self->{'uidBackup'} = \%uidBackup;
    $self->{'gidBackup'} = \%gidBackup;

    $self->{'noDirs'} = 0;      # number of directories in backup
    $self->{'noFiles'} = 0;     # overall number of files in backup
    $self->{'noSymLinks'} = 0;  # number of symbolic links in backup
    $self->{'noLateLinks'} = 0; # number of files with lateLinks in
                                # backup, each blocked file fragment
                                # increases this number
    $self->{'noNamedPipes'} = 0;# number of named pipes in backup
    $self->{'noSockets'} = 0;   # number of sockets in backup
    $self->{'noCharDev'} = 0;   # number of character devices in backup
    $self->{'noBlockDev'} = 0;  # number of block devices in backup
    $self->{'noMD5edFiles'} = 0;# number of files where an md5 sum was
                                # calculated, each blocked file fragment
                                # increases this number
    $self->{'noInternalLinkedFiles'} = 0;# number of files which were linked
                                # inside the just running backup
    $self->{'noOldLinkedFiles'} = 0;# number of files which were linked
                                # to other backups
    $self->{'unchangedFiles'} = 0;# size of files, where size and
                                # timestamp were not changed since the
                                # last backup, they were directly linked
                                # and the md5 sum was not calculated again
    $self->{'noCopiedFiles'} = 0;# number of files which were copied
    $self->{'noCompressedFiles'} = 0;# number of files which were compressed
    $self->{'noForksMD5'} = 0;  # number of forks to calcluated an md5
    $self->{'noForksCP'} = 0;   # number of forks to copy a file
    $self->{'noForksCompress'} = 0;# number of forks to compress a file
    $self->{'noExcludeRule'} = 0;# number of files excluded because of
                                # exclude rule
    $self->{'sizeExcludeRule'} = 0;# size of files excluded because of
                                # exclude rule
    $self->{'noIncludeRule'} = 0;# number of files included because of
                                # include rule
    $self->{'sizeIncludeRule'} = 0;# size of files included because of
                                # include rule
    $self->{'noBlockedFiles'} = 0;# number of files treated as blocked
                                # files (because of blocked rules)
    $self->{'noComprCheckCompr'} = 0;# number of files compressed because
                                # of COMPRESSION_CHECK rule
    $self->{'noComprCheckCp'} = 0;# number of files copied because
                                # of COMPRESSION_CHECK rule
    $self->{'noBlockComprCheckCompr'} = 0;# number of files in blocked
                                # files directories compressed because
                                # of COMPRESSION_CHECK
    $self->{'noBlockComprCheckCp'} = 0;# number of files in blocked
                                # files directories copied because
                                # of COMPRESSION_CHECK

    # disk space related
    $self->{'sumOrigFiles'} = 0;# size of files in source dir
    $self->{'sumMD5Sum'} = 0;   # number of bytes for which an md5 sum
                                # was calculated
    $self->{'sumLinkedInternalCopy'} = 0;# size of files which were linked
                                # inside the just running backup
    $self->{'sumLinkedInternalCompr'} = 0;# size of files which were linked
                                # to other backups
    $self->{'sumLinkedOldCopy'} = 0;# size of files which were linked to
                                # other (old) backups
    $self->{'sumLinkedOldCompr'} = 0;# size of files which were linked to
                                # other (old) backups
    $self->{'sumUnchangedCopy'} = 0;# size of files, where size and
                                # timestamp were not changed since the
                                # last backup, they were directly linked
                                # and the md5 sum was not calculated again
    $self->{'sumUnchangedCompr'} = 0;# size of files, where size and
                                # timestamp were not changed since the
                                # last backup, they were directly linked
                                # and the md5 sum was not calculated again
    $self->{'sumNewCopy'} = 0;  # sum of newly copyied files into the
                                # backup
    $self->{'sumNewCompr'} = 0; # sum of newly compressed files into
                                # the backup (compressed size)
    $self->{'sumNewComprOrigSize'} = 0;# sum of newy compressed files
                                # into the backup (uncompressed size)

    $self->{'md5CheckSum'} = 0;
    $self->{'sumDBMFiles'} = 0;

    $self->{'timeProgrReport'} =
	($self->{'progressDeltaTime'} > 0) ? time : 0;

    bless $self, $class;
}


########################################
sub incr_noDeletedOldDirs
{
    my $self = shift;

    $self->statisticDeleteOldBackupDirs::incr_noDeletedOldDirs();
}


########################################
sub incr_noDirs
{
    my $self = shift;
    my ($uid, $gid) = @_;

    ++$self->{'noDirs'};

    if ($self->{'userGroupFlag'})
    {
	++$self->{'uidStatInodes'}->{$uid};
	++$self->{'gidStatInodes'}->{$gid};
    }
}


########################################
sub add_noMD5edFiles
{
    my $self = shift;

    $self->{'noMD5edFiles'} += shift;
}


########################################
sub incr_noSymLinks
{
    my $self = shift;
    my ($uid, $gid) = @_;

    ++$self->{'noSymLinks'};
    $self->addSumOrigFiles(0, $uid, $gid);
}

########################################
sub incr_noLateLinks
{
    my $self = shift;
    my ($uid, $gid, $n) = @_;
    $n = 1 unless defined $n;

    $self->{'noLateLinks'} += $n;
}


########################################
sub incr_noNamedPipes
{
    my $self = shift;
    my ($uid, $gid) = @_;

    ++$self->{'noNamedPipes'};
    $self->addSumOrigFiles(0, $uid, $gid);
}


########################################
sub incr_noSockets
{
    my $self = shift;
    my ($uid, $gid) = @_;

    ++$self->{'noSockets'};
    $self->addSumOrigFiles(0, $uid, $gid);
}


########################################
sub incr_noCharDev
{
    my $self = shift;
    my ($uid, $gid) = @_;

    ++$self->{'noCharDev'};
    $self->addSumOrigFiles(0, $uid, $gid);
}


########################################
sub incr_noBlockDev
{
    my $self = shift;
    my ($uid, $gid) = @_;

    ++$self->{'noBlockDev'};
    $self->addSumOrigFiles(0, $uid, $gid);
}


########################################
sub incr_noForksMD5
{
    my $self = shift;
    ++$self->{'noForksMD5'};
}


########################################
sub incr_noForksCP
{
    my $self = shift;
    my $n = shift;
    $n = 1 unless defined $n;

    $self->{'noForksCP'} += $n;
}


########################################
sub incr_noForksCompress
{
    my $self = shift;
    my $n = shift;
    $n = 1 unless defined $n;

    $self->{'noForksCompress'} += $n;
}


########################################
sub incr_noExcludeRule
{
    my $self = shift;
    my $size = shift;
    ++$self->{'noExcludeRule'};
    $self->{'sizeExcludeRule'} += $size;
}


########################################
sub incr_noIncludeRule
{
    my $self = shift;
    my $size = shift;
    ++$self->{'noIncludeRule'};
    $self->{'sizeIncludeRule'} += $size;
}


########################################
sub incr_noBlockedFiles
{
    my $self = shift;
    ++$self->{'noBlockedFiles'};
}


########################################
sub incr_noComprCheckCompr
{
    my $self = shift;
    ++$self->{'noComprCheckCompr'};
}


########################################
sub incr_noComprCheckCp
{
    my $self = shift;
    ++$self->{'noComprCheckCp'};
}


########################################
sub addSumBlockComprCheckCompr
{
    my $self = shift;
    my $n = shift;
    $self->{'noBlockComprCheckCompr'} += $n;
}


########################################
sub addSumBlockComprCheckCp
{
    my $self = shift;
    my $n = shift;
    $self->{'noBlockComprCheckCp'} += $n;
}


########################################
sub addFreedSpace
{
    my $self = shift;

    $self->statisticDeleteOldBackupDirs::addFreedSpace(@_);
}


########################################
sub addSumOrigFiles       # in byte
{
    my $self = shift;
    my ($size, $uid, $gid) = @_;

    $self->{'sumOrigFiles'} += $size;

    ++$self->{'noFiles'};
    $self->printProgressReport()
	if ($self->{'progressReport'} and
	    $self->{'noFiles'} % $self->{'progressReport'} == 0);

    if ($self->{'userGroupFlag'})
    {

	++$self->{'uidStatInodes'}->{$uid};
	++$self->{'gidStatInodes'}->{$gid};
	$self->{'uidStatSize'}->{$uid} += $size;
	$self->{'gidStatSize'}->{$gid} += $size;
    }
}


########################################
sub printProgressReport
{
    my $self = shift;

    if ($self->{'progressReport'} > 0)
    {
	$self->__printProgressReport();
    }
}


########################################
sub checkPrintTimeProgressReport
{
    my $self = shift;

    if ($self->{'timeProgrReport'} > 0 and
	time >= $self->{'timeProgrReport'} + $self->{'progressDeltaTime'})
    {
	$self->__printProgressReport();
    }
}


########################################
sub __printProgressReport
{
    my $self = shift;

    my $s = $self->{'sumNewCompr'} + $self->{'sumNewCopy'};
    $self->{'prLog'}->print('-kind' => 'P',
			    '-str' =>
			    [$self->{'noFiles'} . ' files processed (' .
			     (&::humanReadable($self->{'sumOrigFiles'}))[0] .
			     ', ' .
			     (&::humanReadable($s))[0] . ') (' .
			     $self->{'sumOrigFiles'} . ', ' . $s . ')']);

    $self->{'timeProgrReport'} = time
	if $self->{'timeProgrReport'} > 0;
}


########################################
sub addSumMD5Sum       # in byte
{
    my $self = shift;

    $self->{'sumMD5Sum'} += shift;
}


########################################
sub addSumLinkedInternalCopy   # byte
{
    my $self = shift;

    $self->{'sumLinkedInternalCopy'} += shift;
    ++$self->{'noInternalLinkedFiles'};
}


########################################
sub addSumLinkedInternalCompr   # byte
{
    my $self = shift;

    $self->{'sumLinkedInternalCompr'} += shift;
    ++$self->{'noInternalLinkedFiles'};
}



########################################
sub addSumLinkedOldCopy   # byte
{
    my $self = shift;

    $self->{'sumLinkedOldCopy'} += shift;
    ++$self->{'noOldLinkedFiles'};
}


########################################
sub addSumLinkedOldCompr   # byte
{
    my $self = shift;

    $self->{'sumLinkedOldCompr'} += shift;
    ++$self->{'noOldLinkedFiles'};
}


########################################
sub addSumUnchangedCopy   # byte
{
    my $self = shift;

    $self->{'sumUnchangedCopy'} += shift;
    ++$self->{'unchangedFiles'};
}


########################################
sub addSumUnchangedCompr   # byte
{
    my $self = shift;

    $self->{'sumUnchangedCompr'} += shift;
    ++$self->{'unchangedFiles'};
}


########################################
sub addSumNewCopy   # byte
{
    my $self = shift;
    my $a = shift;

    $self->{'sumNewCopy'} += $a ? $a : 0;
    ++$self->{'noCopiedFiles'};
}


########################################
sub addSumNewCompr   # byte
{
    my $self = shift;
    my $a1 = shift;
    my $a2 = shift;

    $self->{'sumNewCompr'} += $a1 ? $a1 : 0;
    $self->{'sumNewComprOrigSize'} += $a2 ? $a2 : 0;
    ++$self->{'noCompressedFiles'};
}


########################################
sub addSumDBMFiles    # byte
{
    my $self = shift;

    $self->{'sumDBMFiles'} += shift;
}


########################################
sub setSizeMD5CheckSum
{
    my $self = shift;
    my $md5CheckSum = shift;
    my $compressMD5File = shift;

    if ($compressMD5File eq 'yes')
    {
	$self->{'md5CheckSum'} = (stat("$md5CheckSum.bz2"))[7];
    }
    else
    {
	$self->{'md5CheckSum'} = (stat($md5CheckSum))[7];
    }
}


########################################
sub setUsedSizeQueues
{
    my $self = shift;

    $self->{'maxUsedCopyQueue'} = shift;
    $self->{'maxUsedComprQueue'} = shift;
}


########################################
sub print
{
    my $self = shift;

    my (%params) = ('-exTypes' => []
		    );

    &::checkObjectParams(\%params, \@_, 'Statistic::print', ['-exTypes']);

    my $exTypes = $params{'-exTypes'};
    my (@exTypes, $et);
    my %exTypesLines = ('S' => 'socket',
			'b' => 'block special',
			'c' => 'char special',
			'f' => 'plain file',
			'p' => 'named pipe',
			'l' => 'symbolic link');
    foreach $et (keys %$exTypes)
    {
	push @exTypes, sprintf("%33s", "excluded " .
			       $exTypesLines{$et} .
			       "s ($et) = ") . $$exTypes{$et};
    }

    my (@l);
    my ($user,$system,$cuser,$csystem) = times;
    my ($trenn) = "-------+----------+----------";
    push @l, sprintf("%-7s|%10s|%10s", " [sec]", "user", "system");
    push @l, "$trenn";
    push @l, sprintf("%-7s|%10.2f|%10.2f", "process", $user, $system);
    push @l, sprintf("%-7s|%10.2f|%10.2f", "childs", $cuser, $csystem);
    push @l, "$trenn";
    my ($u, $s) = ($cuser + $user, $csystem + $system);
    $u = .1 if $u + $s == 0;       # avoid division by zero
    my $us_str = &dateTools::valToStr('-sec' => int($u + $s + .5));
    push @l, sprintf("%-7s|%10.2f|%10.2f => %.2f ($us_str)", "sum",
		     $u, $s, $u + $s);

    my $startDate = $self->{'startDate'};
    my (@startDate) = ();
    if ($startDate)
    {
	push @startDate, '           precommand duration = ' .
	    $startDate->deltaInStr('-secondDate' => $self->{'aktDate'});
    }

    my $dEnd = dateTools->new();
    my $backupDuration =
	$self->{'aktDate'}->deltaInSecs('-secondDate' => $dEnd);
    $backupDuration = 1 if ($backupDuration == 0);   # Minimaler Wert

    my $sumTargetAll =
	$self->{'sumLinkedInternalCopy'} +
	$self->{'sumLinkedInternalCompr'} +
	$self->{'sumLinkedOldCopy'} +
	$self->{'sumLinkedOldCompr'} +
	$self->{'sumNewCopy'} +
	$self->{'sumNewCompr'};

    my $sumTargetNew = $self->{'sumNewCopy'} + $self->{'sumNewCompr'};

    my $newUsedSpace = $sumTargetNew + $self->{'md5CheckSum'} -
	$self->{'bytes'};
    my $newUsedSpaceHuman;
    if ($newUsedSpace >= 0)
    {
	($newUsedSpaceHuman) = &::humanReadable($newUsedSpace);
    }
    else
    {
	($newUsedSpaceHuman) = &::humanReadable(- $newUsedSpace);
	$newUsedSpaceHuman = "-$newUsedSpaceHuman";
    }

    my (@ug_log) = ();
    my (@ug_file) = ();
    if ($self->{'userGroupFlag'})
    {
	my $k;
	my $uidStatInodes = $self->{'uidStatInodes'};
	foreach $k (sort {$a <=> $b} keys %$uidStatInodes)
	{
	    my $name = getpwuid($k);
	    $name = '-' unless $name;
	    push @ug_log, sprintf("USER INODE  %6d - %9s = %lu",
				   $k, $name, $$uidStatInodes{$k});
	    push @ug_file, "USER_INODE $k $name " . $$uidStatInodes{$k};
	}
	my $uidStatSize = $self->{'uidStatSize'};
	foreach $k (sort {$a <=> $b} keys %$uidStatSize)
	{
	    my $name = getpwuid($k);
	    $name = '-' unless $name;
	    push @ug_log, sprintf("USER SIZE   %6d - %9s = %s (%lu)",
				  $k, $name,
				  (&::humanReadable($$uidStatSize{$k}))[0],
				  $$uidStatSize{$k});
	    push @ug_file, "USER_SIZE $k $name " . $$uidStatSize{$k};
	}

	my $gidStatInodes = $self->{'gidStatInodes'};
	foreach $k (sort {$a <=> $b} keys %$gidStatInodes)
	{
	    my $group = getgrgid($k);
	    $group = '-' unless $group;
	    push @ug_log, sprintf("GROUP INODE %6d - %9s = %lu",
				   $k, $group, $$gidStatInodes{$k});
	    push @ug_file, "GROUP_INODE $k $group " . $$gidStatInodes{$k};
	}
	my $gidStatSize = $self->{'gidStatSize'};
	foreach $k (sort {$a <=> $b} keys %$gidStatSize)
	{
	    my $group = getgrgid($k);
	    $group = '-' unless $group;
	    push @ug_log, sprintf("GROUP SIZE  %6d - %9s = %s (%lu)",
				  $k, $group,
				  (&::humanReadable($$gidStatSize{$k}))[0],
				  $$gidStatSize{$k});
	    push @ug_file, "GROUP_SIZE $k $group " . $$gidStatSize{$k};
	}

#	print "#################\n";
#	print join("\n", @ug_log), "\n";
#	print "#################\n";
#	print join("\n", @ug_file), "\n";

	my $file = $self->{'userGroupStatFile'};
	if ($file)
	{
	    local *FILE;
	    &::checkDelSymLink($file, $prLog, 0x01);
	    unless (open(FILE, "> $file"))
	    {
		$prLog->print('-kind' => 'E',
			      '-str' => ["cannot write statistic to <$file>"]);
		goto endUidGid;
	    }
	    print FILE join("\n", @ug_file), "\n";
	    close(FILE);
	    $prLog->print('-kind' => 'I',
			  '-str' => ["printed userGroupStatFile <$file>"]);
	}
      endUidGid:;
    }

    my (@comprCheck) = ();
    if ($self->{'noComprCheckCompr'} + $self->{'noComprCheckCp'} > 0)
    {
	push @comprCheck,
	'compr due to COMPRESSION_CHECK = ' . $self->{'noComprCheckCompr'},
	'   cp due to COMPRESSION_CHECK = ' . $self->{'noComprCheckCp'};
    }
    my (@blockComprCheck) = ();
    if ($self->{'noBlockComprCheckCompr'} + $self->{'noBlockComprCheckCp'} > 0)
    {
	push @blockComprCheck,
	'blockedFiles: comp COMPR_CHECK = ' . $self->{'noBlockComprCheckCompr'},
	'  blockedFiles: cp COMPR_CHECK = ' . $self->{'noBlockComprCheckCp'};
    }

    $self->{'prLog'}->
	print('-kind' => 'S',
	      '-str' =>
	      [@l,
	       @ug_log,
	       '                   directories = ' . $self->{'noDirs'},
	       '                         files = ' . $self->{'noFiles'},
	       '                symbolic links = ' . $self->{'noSymLinks'},
	       '                    late links = ' . $self->{'noLateLinks'},
	       '                   named pipes = ' . $self->{'noNamedPipes'},
	       '                       sockets = ' . $self->{'noSockets'},
	       '                 block devices = ' . $self->{'noBlockDev'},
	       '             character devices = ' . $self->{'noCharDev'},
	       '     new internal linked files = ' .
	           $self->{'noInternalLinkedFiles'},
	       '              old linked files = ' . $self->{'noOldLinkedFiles'},
	       '               unchanged files = ' . $self->{'unchangedFiles'},
	       '                  copied files = ' . $self->{'noCopiedFiles'},
	       '              compressed files = ' . $self->{'noCompressedFiles'},
	       '                 blocked files = ' . $self->{'noBlockedFiles'},
	       '   excluded files because rule = ' . $self->{'noExcludeRule'} .
	       ' (' . (&::humanReadable($self->{'sizeExcludeRule'}))[0] . ')',
	       '   included files because rule = ' . $self->{'noIncludeRule'} .
	       ' (' . (&::humanReadable($self->{'sizeIncludeRule'}))[0] . ')',
	       @comprCheck,
	       @blockComprCheck,
	       @exTypes,
	       '        max size of copy queue = ' . $self->{'maxUsedCopyQueue'},
	       ' max size of compression queue = ' . $self->{'maxUsedComprQueue'},

	       '           calculated md5 sums = ' . $self->{'noMD5edFiles'},
	       '                   forks total = ' . ($self->{'noForksMD5'} +
						   $self->{'noForksCP'} +
						   $self->{'noForksCompress'} +
						   $self->{'noNamedPipes'}),
	       '                     forks md5 = ' . $self->{'noForksMD5'},
	       '                    forks copy = ' . $self->{'noForksCP'},
	       sprintf("%33s", "forks " . join(' ', @{$self->{'compress'}})
		       . " = ") . $self->{'noForksCompress'},

	       '                 sum of source = ' .
	           (&::humanReadable($self->{'sumOrigFiles'}))[0] .
	           ' (' . $self->{'sumOrigFiles'} . ')',
	       '             sum of target all = ' .
	           (&::humanReadable($sumTargetAll))[0] . " ($sumTargetAll)",
	       '             sum of target all = ' . sprintf("%.2f%%",
		   &percent($self->{'sumOrigFiles'}, $sumTargetAll)),
	       '             sum of target new = ' .
	           (&::humanReadable($sumTargetNew))[0] . " ($sumTargetNew)",
	       '             sum of target new = ' .  sprintf("%.2f%%",
		   &percent($self->{'sumOrigFiles'}, $sumTargetNew)),
	       '            sum of md5ed files = ' .
	           (&::humanReadable($self->{'sumMD5Sum'}))[0] .
	           ' (' . $self->{'sumMD5Sum'} . ')',
	       '            sum of md5ed files = ' . sprintf("%.2f%%",
		   &percent($self->{'sumOrigFiles'},
			    $self->{'sumMD5Sum'})),
	       '    sum internal linked (copy) = ' .
	           (&::humanReadable($self->{'sumLinkedInternalCopy'}))[0] .
	           ' (' . $self->{'sumLinkedInternalCopy'} . ')',
	       '   sum internal linked (compr) = ' .
	           (&::humanReadable($self->{'sumLinkedInternalCompr'}))[0] .
	           ' (' . $self->{'sumLinkedInternalCompr'} . ')',
	       '         sum old linked (copy) = ' .
	           (&::humanReadable($self->{'sumLinkedOldCopy'}))[0] .
	           ' (' . $self->{'sumLinkedOldCopy'} . ')',
	       '        sum old linked (compr) = ' .
	           (&::humanReadable($self->{'sumLinkedOldCompr'}))[0] .
	           ' (' . $self->{'sumLinkedOldCompr'} . ')',
	       '          sum unchanged (copy) = ' .
	           (&::humanReadable($self->{'sumUnchangedCopy'}))[0] .
	           ' (' . $self->{'sumUnchangedCopy'} . ')',
	       '         sum unchanged (compr) = ' .
	           (&::humanReadable($self->{'sumUnchangedCompr'}))[0] .
	           ' (' . $self->{'sumUnchangedCompr'} . ')',
	       '                sum new (copy) = ' .
	           (&::humanReadable($self->{'sumNewCopy'}))[0] .
	           ' (' . $self->{'sumNewCopy'} . ')',
	       '               sum new (compr) = ' .
	           (&::humanReadable($self->{'sumNewCompr'}))[0] .
	           ' (' . $self->{'sumNewCompr'} . ')',
	       '    sum new (compr), orig size = ' .
	           (&::humanReadable($self->{'sumNewComprOrigSize'}))[0] .
	           ' (' . $self->{'sumNewComprOrigSize'} . ')',
	       '                sum new / orig = ' . sprintf("%.2f%%",
	           &percent($self->{'sumNewComprOrigSize'}
			    + $self->{'sumNewCopy'},
			    $self->{'sumNewCompr'}
			    + $self->{'sumNewCopy'})),
	       '      size of md5CheckSum file = ' .
	           (&::humanReadable($self->{'md5CheckSum'}))[0] .
	           ' (' . $self->{'md5CheckSum'} . ')',
	       '    size of temporary db files = ' .
	           (&::humanReadable($self->{'sumDBMFiles'}))[0] .
	           ' (' . $self->{'sumDBMFiles'} . ')',
	       @startDate,
	       '           deleted old backups = ' . $self->{'noDeletedOldDirs'},
	       '           deleted directories = ' . $self->{'dirs'},
	       '                 deleted files = ' . $self->{'files'},
	       '          (only) removed links = ' . $self->{'links'},
	       'freed space in old directories = ' .
	       (&::humanReadable($self->{'bytes'}))[0] . ' (' .
	       $self->{'bytes'} . ')',
	       "      add. used space in files = $newUsedSpaceHuman ($newUsedSpace)",
	       '               backup duration = ' .
	       dateTools::valToStr('-sec' => $backupDuration),
	       'over all files/sec (real time) = ' .
	           sprintf("%.2f", $self->{'noFiles'} / $backupDuration),
	       ' over all files/sec (CPU time) = ' .
	           sprintf("%.2f", $self->{'noFiles'} / ($u + $s)),
	       '                     CPU usage = ' .
	           sprintf("%.2f%%", ($u + $s) / $backupDuration * 100)
	       ]);

}


########################################
sub percent
{
    my ($base, $rel) = @_;

    if ($base == 0)
    {
	return 0;
    }
    else
    {
	return 100 - ($base - $rel) * 100 / $base;
    }
}



######################################################################
# stores Dates and Times of all directories in a file
# after backup this file is read and directory atime and mtime are set
package setResetDirTimes;

########################################
sub new
{
    my $class = shift;
    my $self = {};

    my (%params) = ('-tmpDir'    => undef,
		    '-sourceDir' => undef,
		    '-targetDir' => undef,
		    '-prLog'     => undef,
		    '-srdtf'     => undef,
		    '-doNothing' => 0,
		    '-resetAtime' => 0,
		    '-preservePerms' => undef
		    );

    &::checkObjectParams(\%params, \@_, 'setResetDirTimes::new',
			 ['-tmpDir', '-sourceDir', '-targetDir', '-prLog',
			  '-srdtf']);

    &::setParamsDirect($self, \%params);

    unless ($self->{'doNothing'})
    {
	my $tmpfile = &::uniqFileName("$tmpdir/storeBackup-dirs.");
	$self->{'tmpfile'} = $tmpfile;
	local *FILE;
	&::checkDelSymLink($tmpfile, $prLog, 0x01);
	open(FILE, "> $tmpfile") or
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot open <$tmpfile>, exiting"],
			  '-add' => [__FILE__, __LINE__],
			  '-exit' => 1);
	chmod 0600, $tmpfile;
	$self->{'FILE'} = *FILE;
    }

    bless $self, $class;
}


########################################
sub addDir
{
    my $self = shift;
    my ($relFile, $atime, $mtime, $mode) = @_;

    return if $self->{'doNothing'};

    local *FILE = $self->{'FILE'};
    $relFile =~ s/\n/\0/og;
    print FILE "$atime $mtime $mode $relFile\n";
}


########################################
sub writeTimes
{
    my $self = shift;

    return if $self->{'doNothing'};

    my $sourceDir = $self->{'sourceDir'};
    my $targetDir = $self->{'targetDir'};
    local *FILE = $self->{'FILE'};
    my $prLog = $self->{'prLog'};
    my $tmpfile = $self->{'tmpfile'};

    close(FILE) or
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot close <$tmpfile>"]);

    if ($self->{'preservePerms'})
    {
	unless (open(FILE, "< $tmpfile"))
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["cannot read <$tmpfile>, cannot set atime " .
				     "and mtime for directories"]);
	    return;
	}

	unless (eof FILE)
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["setting atime, mtime of directories ..."]);
	}

	my $line;
	while ($line = <FILE>)
	{
	    chop $line;
	    my ($atime, $mtime, $mode, $relFile) = split(/\s/, $line, 4);
	    $relFile =~ s/\0/\n/og;
	    chmod $mode, "$targetDir/$relFile";
	    utime $atime, $mtime, "$sourceDir/$relFile" if $self->{'resetAtime'};
	    utime $atime, $mtime, "$targetDir/$relFile";
	}

	close(FILE);
    }
    else
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["directory permissions not set because " .
				 "preservePerms not set"]);
    }
    unlink $tmpfile;
}
