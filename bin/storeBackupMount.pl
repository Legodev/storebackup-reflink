#! /usr/bin/env perl

#
#   Copyright (C) Dr. Heinz-Josef Claes (2004-2014)
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

require 'checkParam2.pl';
require 'checkObjPar.pl';
require 'prLog.pl';
require 'forkProc.pl';
require 'dateTools.pl';
require 'version.pl';
require 'fileDir.pl';

$main::exit = 0;                               # exit status

my $tmpdir = '/tmp';              # default value
$tmpdir = $ENV{'TMPDIR'} if defined $ENV{'TMPDIR'};

=head1 NAME

Mounts file systems (defined in /etc/fstab) and starts storeBackup
related programs
if you use command line, the order of execution depends on the order
of the --storeBackup* options
if you use the configuration file, the oder of execution depends on
option 'orderOfExecution'

=head1 SYNOPSIS

        storeBackupMount.pl --help
or
        storeBackupMount.pl -g configFile
or
        storeBackupMount.pl -f configFile
or
	storeBackupMount.pl [-s servers] [-d] [-l logFile
	       [--suppressTime] [-m maxFilelen]
	       [[-n noOfOldFiles] | [--saveLogs]]
	       [--compressWith compressprog]]
	    [--storeBackup storeBackup-Params]
	    [--storeBackupUpdateBackup storeBackupUpdateBackup-Params]
	    [--storeBackupCheckBackup storeBackupCheckBackup-Params]
	    [--storeBackupCheckSource storeBackupCheckSource-Params]
	    [--storeBackupDel storeBackupDel-Params]
	    [--printAndStop] [-k killTime] [-T tmpdir] [mountPoints...]

=head1 DESCRIPTION

This script does the following:

=over 4

=item - checks an nfs server with ping

=item - mounts that server via a list of mount points

=item - starts storeBackup (with a config file)

=item - umounts that server

=back

=head1 OPTIONS

=over 8

=item B<--help>

    show this help

=item B<--generate>, B<-g>

    generate a template of the configuration file

=item B<--file>, B<-f>

    configuration file (instead of or additionally to options
    on command line)

=item B<--servers>, B<-s>

    name(s) or ip address(es) of the nfs server(s)
    This option can be repeated multiple times

=item B<--debug>, B<-d>

    generate some debug messages

=item B<--logFile>, B<-l>

    logFile for this process.
    default is STDOUT.

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

=item B<--storeBackup>

      run storeBackup.pl
      use this parameter as options for storeBackup.pl
      This parameter is parsed like the line in the
      configuration file and normally has to be quoted,
      eg. '-f stbu.conf'

=item B<--storeBackupUpdateBackup>

      run storeBackupUpdateBackup.pl
      use this parameter as options for storeBackupUpdateBackup.pl
      This parameter is parsed like the line in the
      configuration file and normally has to be quoted,
      eg. '-b /backupDir'

=item B<--storeBackupCheckBackup>

      run storeBackupCheckBackup.pl
      use this parameter as options for storeBackupCheckBackup.pl
      This parameter is parsed like the line in the
      configuration file and normally has to be quoted,
      eg. '-c /backupDir'

=item B<--storeBackupCheckSource>

      run storeBackupCheckSource.pl
      use this parameter as options for storeBackupCheckSource.pl
      This parameter is parsed like the line in the
      configuration file and normally has to be quoted,
      eg. '-s /home/bob -b /backupDir'

=item B<--storeBackupDel>

      run storeBackupDel.pl
      use this parameter as options for storeBackupDel.pl
      This parameter is parsed like the line in the
      configuration file and normally has to be quoted,
      eg. '-f stbu.conf'

=item B<--printAndStop>, B<-p>

      print options and stop processing

=item B<--killTime> B<-k>

    time until any of the programs started will be killed.
    default is 365 days.
    the time range has to be specified in format 'dhms', e.g.
    10d4h means 10 days and 4 hours

=item B<--tmpdir>, B<-T>

    directory for temporary files, default is </tmp>

=item F<mountPoints>

    List of mount points needed to perform the backup.
    This must be a list of paths which have to be
    defined in /etc/fstab.
    -
    if you add 'ro,' or 'rw,' to the beginning of a mount
    point, you can overwrite that option set in /etc/fstab

    example:
    ro,/fileSystemToRead
       will mount /fileSystemToRead read only, even if the
       corresponding entry in /etc/fstab mounts is read/write

    only root is allowed to use this feature!

=back

=head1 EXIT STATUS

=over 4

=item 0 -> everything is ok

=item 1 -> error from called program

=item 2 -> error from storeBackupMount

=item 3 -> error from both programs

=back

=head1 COPYRIGHT

Copyright (c) 2004-2014 by Heinz-Josef Claes (see README).
Published under the GNU General Public License v3 or any later version

=cut

my $Help = &::getPod2Text($0);

my $templateConfigFile = <<EOC;
# configuration file for storeBackupMount.pl, version $main::STOREBACKUPVERSION

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
# '--unset logFile' or '--unset --logFile'

# name(s) or ip address(es) of the nfs server(s)
;servers=

# List of mount points needed to perform the backup.
#This must be a list of paths which have to be
# defined in /etc/fstab.
#
# if you add 'ro,' or 'rw,' to the beginning of a mount
#  point, you can overwrite that option set in /etc/fstab
# example:
# ro,/filesSystemToRead
# will mount /fileSystemToRead read only, even if the
# corresponding entry in /etc/fstab mounts it read write
# only root is allowed to use this feature!
;mountPoints=

# generate some debug messages
;debug=

# logFile for this process.
# default is STDOUT.
;logFile=

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

# run storeBackup.pl
# use this parameter to define the options for storeBackup.pl, eg.:
# -f stbu.conf
;storeBackup=

# run storeBackupUpdateBackup.pl
# use this parameter to define the options for storeBackupUpdateBackup.pl, eg.:
# -b /backupDir
;storeBackupUpdateBackup=

# run storeBackupCheckBackup.pl
# use this parameter to define the options for storeBackupCheckBackup.pl, eg.:
# '-c /backupDir'
;storeBackupCheckBackup=

# run storeBackupCheckSource.pl
# use this parameter to define the options for storeBackupCheckSource.pl, eg.:
# -s /home/bob -b /backupDir
;storeBackupCheckSource=

# run storeBackupDel.pl
# use this parameter to define the options for storeBackupDel.pl, eg.:
# -f stbu.conf
;storeBackupDel=

# order or execution of the commands specified above
# default is:
#
# storeBackup storeBackupUpdateBackup storeBackupCheckBackup
# storeBackupCheckSource storeBackupDel
;orderOfExecution=

# time until storeBackup.pl will be killed.
# default is 365 days.
# the time range has to be specified in format 'dhms', e.g.
# 10d4h means 10 days and 4 hours
;killTime=

# directory for temporary file, default is /tmp
;tmpDir=
EOC
    ;



&printVersion(\@ARGV, '-V', '--version');

my (@progs) = ('storeBackup', 'storeBackupUpdateBackup', 'storeBackupCheckBackup',
	       'storeBackupCheckSource', 'storeBackupDel');
my (@progOpts);
foreach my $p (@progs)
{
    push @progOpts,
    Option->new('-name' => $p,
		'-cl_option' => "--$p",
		'-quoteEval' => 'yes',
		'-cf_key' => $p,
		'-param' => 'yes');
}
my $CheckPar =
    CheckParam->new('-allowLists' => 'yes',
                    '-listMapping' => 'mountPoints',
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
				Option->new('-name' => 'servers',
					    '-cl_option' => '-s',
					    '-cl_alias' => '--servers',
					    '-cf_key' => 'servers',
					    '-multiple' => 'yes',
					    '-param' => 'yes'),
				Option->new('-name' => 'debug',
					    '-cl_option' => '-d',
					    '-cl_alias' => '--debug',
					    '-cf_key' => 'debug',
					    '-cf_noOptSet' => ['yes', 'no']),
				Option->new('-name' => 'logFile',
					    '-cl_option' => '-l',
					    '-cl_alias' => '--logFile',
					    '-cf_key' => 'logFile',
					    '-param' => 'yes'),
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
				@progOpts,
				Option->new('-name' => 'printAndStop',
					    '-cl_option' => '-p',
					    '-cl_alias' => '--printAndStop'),
				Option->new('-name' => 'killTime',
					    '-cl_option' => '-k',
					    '-cl_alias' => '--killTime',
					    '-cf_key' => 'killTime',
					    '-default' => '365d'),
				Option->new('-name' => 'tmpdir',
					    '-cl_option' => '-T',
					    '-cl_alias' => '--tmpdir',
					    '-cf_key' => 'tmpDir',
					    '-default' => $tmpdir),
                                Option->new('-name' => 'mountPoints',
					    '-cf_key' => 'mountPoints',
					    '-multiple' => 'yes'),
                                Option->new('-name' => 'orderOfExecution',
					    '-cf_key' => 'orderOfExecution',
					    '-default' => \@progs,
					    '-multiple' => 'yes')
				]);
$CheckPar->check('-argv' => \@ARGV,
                 '-help' => $Help
                 );

my $Help = <<EOH;
try '$prog --help' to get a description of the options.
EOH
    ;
# '

my $FullHelp = &::getPod2Text($0);

# Auswertung der Parameter
my $help = $CheckPar->getOptWithoutPar('help');

die "$FullHelp" if $help;

my (%argForProgs);
my $configFile = $CheckPar->getOptWithPar('configFile');
my $generateConfigFile = $CheckPar->getOptWithPar('generate');
my $servers = $CheckPar->getOptWithPar('servers');
my $debug = $CheckPar->getOptWithoutPar('debug');
my $logFile = $CheckPar->getOptWithPar('logFile');
my $withTime = not $CheckPar->getOptWithoutPar('suppressTime');
$withTime = $withTime ? 'yes' : 'no';
my $maxFilelen = $CheckPar->getOptWithPar('maxFilelen');
my $noOfOldFiles = $CheckPar->getOptWithPar('noOfOldFiles');
my $saveLogs = $CheckPar->getOptWithoutPar('saveLogs');
my $compressWith = $CheckPar->getOptWithPar('compressWith');
foreach my $a (@progs)
{
    $argForProgs{$a} = $CheckPar->getOptWithPar($a);
}
my $printAndStop = $CheckPar->getOptWithoutPar('printAndStop');
my $kt = $CheckPar->getOptWithPar('killTime');
$tmpdir = $CheckPar->getOptWithPar('tmpdir');
my (@mountPoints) = $CheckPar->getListPar();
my $orderOfExecution = $CheckPar->getOptWithPar('orderOfExecution');

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



# analyse parameter list for external programs
my (@optOrder) = ();
if ($configFile)
{
    (@optOrder) = (@$orderOfExecution)
}
else
{
    (@optOrder) = $CheckPar->getOptOrder();
}

my (@progsToStart) = ();
foreach my $o (@optOrder)
{
    next unless defined $argForProgs{$o};
    push @progsToStart, $o;
}

if ($printAndStop)
{
    $CheckPar->print();
    print "order of execution\n";
    foreach my $p (@progsToStart)
    {
	print "\t$p: <", join('> <', @{$argForProgs{$p}}), ">\n";
    }
    exit 0;
}

die "$Help"
    unless @progsToStart;


my $pLog = printLog->new('-tmpdir' => $tmpdir);
my $fifo = ::uniqFileName("$tmpdir/prLog-");
POSIX::mkfifo($fifo, 0600) or
    $pLog->print('-kind' => 'E',
		 '-str' => ["cannot mknod <$fifo> for storeBackupMount.pl"],
		 '-exit' => 2);

my (@logArgs) = ();
if ($logFile)
{
#    (@logArgs) = ('--out' => $logFile);
    (@logArgs) = ('--out' => $logFile,
		  '--maxFilelen' => $maxFilelen,
		  '--noOfOldFiles' => $noOfOldFiles,
		  '--compressWith' => $compressWith);
    push @logArgs, '--saveLogs'	if $saveLogs;
}
my $logD = forkProc->new('-exec' => "$req/stbuLog.pl",
			 '-param' => ['--readFile' => $fifo,
				      @logArgs],
			 '-prLog' => $pLog);

my $prLog;
my ($prLogKind) = ['A:BEGIN',
		   'Z:END',
		   'V:VERSION',
		   'I:INFO',
		   'D:DEBUG',
		   'W:WARNING',
		   'E:ERROR'];

if ($logFile)
{
    $prLog = printLog->new('-file' => $fifo,
			   '-kind' => $prLogKind,
			   '-withTime' => $withTime,
			   '-tmpdir' => $tmpdir);
}
else
{
    $prLog = printLog->new('-kind' => $prLogKind,
			   '-withTime' => $withTime,
			   '-tmpdir' => $tmpdir);
}


$prLog->print('-kind' => 'E',
	      '-str' => ["you must specify at least one program to execute"])
    unless @progsToStart;


$prLog->print('-kind' => 'A',
	      '-str' => ["starting storeBackupMount.pl"]);
$prLog->print('-kind' => 'V',
	      '-str' => ["storeBackupMount.pl, $main::STOREBACKUPVERSION"]);

# killTime in seconds:
my $killTime = &dateTools::strToSec('-str' => $kt);
unless (defined $killTime)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["wrong format of parameter --killTime: <$kt>"]);
    exit 2;
}

#
# checking if required programs are there
#
my ($pathToBin) = splitFileDir($0);
my (%progName) = ();
foreach my $p (@progsToStart)
{
    if (-e "$pathToBin/$p")
    {
	$progName{$p} = "$pathToBin/$p";    # debian strips '.pl'
    }
    elsif (-e "$pathToBin/$p.pl")
    {
	$progName{$p} = "$pathToBin/$p.pl";
    }
    else
    {
	$prLog->print('-kind' => 'E',
		      '-str' => ["cannot find ${p}[.pl] at <$pathToBin>"]);
	$main::exit = 2;
    }
}
exit $main::exit if $main::exit;

#
# test ping to servers
#
if ($servers)
{
    foreach my $server (@$servers)
    {
	my $p = Net::Ping->new('tcp', 5); # wait a maximum of 5 seconds
	                                  # for response
	my $ret = $p->ping($server);
	if ($ret == 1)
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["host <$server> reachable via tcp-ping"]);
	}
	else
	{
	    $main::exit |= 2;
	    $prLog->print('-kind' => 'E',
			  '-str' =>
			  ["host <$server> not reachable via tcp-ping"]);
	}
    }
    $prLog->print('-kind' => 'E',
		  '-str' => ["exiting"],
		  '-exit' => $main::exit)
	if ($main::exit);
}

#
# checking for already mounted filesystems
#
my (@aM) = `mount`;
my (%alreadyMounted, $m);
foreach $m (@aM)
{
    $m =~ /(.+?) on (.*) type /;
    $alreadyMounted{$2} = 1;
}

#
# mounting the file systems
#
my (@mounted) = ();
my $error = 0;
foreach $m (@mountPoints)
{
    my (@opt) = ();
    if ($m =~ /\A(r[ow]),(.*)/)
    {
	(@opt) = ('-o', $1);
	$m = $2;
    }

    if (exists $alreadyMounted{$m})
    {
	$prLog->print('-kind' => 'I',
		      '-str' => ["<$m> is already mounted"]);
	next;
    }

    $prLog->print('-kind' => 'I',
		  '-str' => ["trying to mount @opt $m"]);
    my $fp = forkProc->new('-exec' => 'mount',
			   '-param' => [@opt, $m],
			   '-outRandom' => "$tmpdir/doStoreBackup-forkMount-",
			   '-prLog' => $prLog);

    # wait for a maximum of 10 seconds
    foreach (1..20)
    {
	select(undef, undef, undef, 0.5);
	if ($fp->processRuns() == 0)
	{
	    last;
	}
	else
	{
	    $prLog->print('-kind' => 'D',
			  '-str' => ["waiting for mount command ..."])
		if $debug;
	}
    }
    my $out1 = $fp->getSTDOUT();
    my $out2 = $fp->getSTDERR();
    $fp->DESTROY();
    if ($fp->get('-what' => 'status') != 0    # mount not successfull
	or @$out2 > 0)
    {
	$main::exit |= 2;
	$error = 1;

	$prLog->print('-kind' => 'E',
		      '-str' => ["could not mount @opt $m"]);
	$fp->signal('-value' => 9);

	&umount(\@mounted, \%alreadyMounted, $debug);

	$prLog->print('-kind' => 'E',
		      '-str' => ["exiting"]);
	goto endOfProgram;
    }
    else
    {
	push @mounted, $m;
	$prLog->print('-kind' => 'I',
		      '-str' => ["<mount $m> successfull"]);
    }

    $prLog->print('-kind' => 'W',
		  '-str' => ["STDOUT of <mount $m>:", @$out1])
	if (@$out1 > 0);
    $prLog->print('-kind' => 'E',
		  '-str' => ["STDERR of <mount $m>:", @$out2])
	if (@$out2 > 0);

    if (@$out2)
    {
	$main::exit |= 2;
	$prLog->print('-kind' => 'E',
		      '-str' => ["exiting"]);
	goto endOfProgram;
    }
}
if ($error == 1)
{
    $prLog->print('-kind' => 'E',
		  '-str' => ["exiting"]);
    goto endOfProgram;
}


#
# start programs
#
foreach my $p (@progsToStart)
{
    my $prog = $progName{$p};
    my $params = $argForProgs{$p};

    $prLog->print('-kind' => 'I',
		  '-str' => ["starting $prog @$params"]);
    my $stbu = forkProc->new('-exec' => "$prog",
			     '-param' => [@$params,
					  '--writeToNamedPipe' => $fifo],
			     '-outRandom' => "$tmpdir/doStoreBackup-stbu-",
			     '-prLog' => $prLog);

    if ($killTime)
    {
	my $ready = 0;
	foreach (1..$killTime)
	{
	    sleep 1;
	    if ($stbu->processRuns() == 0)
	    {
		$ready = 1;
		my $status;
		if ($status = $stbu->get('-what' => 'status'))
		{
		    $prLog->print('-kind' => 'E',
				  '-str' =>
				  ["<$prog> exited with status <$status>",
				   "exiting"]);
		    goto endOfProgram;
		}
		last;
	    }
	}
	if ($ready == 0)      # duration too long
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["time limit <$kt> exceeded for " .
				     "<$prog @$params>"]);
	    $stbu->signal('-value' => 2);     # SIGINT
	    $main::exit |= 1;
	    sleep 10;          # time for program to finish
	    unlink $fifo;
	    $prLog->print('-kind' => 'E',
			  '-str' => ["terminating execution"]);
	    goto endOfProgram;
	}
    }
}

endOfProgram:;

unlink $fifo;

&umount(\@mounted, \%alreadyMounted, $debug);

$prLog->print('-kind' => 'Z',
	      '-str' => ["finished storeBackupMount.pl"]);

$prLog->__reallyPrint(['__FINISH__'])
    if ($logFile);

sleep 1;

kill 19, $logD->get('-what' => 'pid');

exit $main::exit;




######################################################################
sub umount
{
    my ($mounted, $alreadyMounted, $debug) = @_;

    foreach $m (reverse @$mounted)
    {
	if (exists $alreadyMounted{$m})
	{
	    $prLog->print('-kind' => 'I',
			  '-str' =>
			  ["do not umount <$m>, was already mounted"]);
	    next;
	}
	$prLog->print('-kind' => 'I',
		      '-str' => ["trying to <umount $m>"]);
	sleep 5;
	my $um = forkProc->new('-exec' => 'umount',
			       '-param' => [$m],
			       '-outRandom' =>
			       "$tmpdir/doStoreBackup-forkMount-",
			       '-prLog' => $prLog);

	# wait for a maximum of 60 seconds
	foreach (1..120)
	{
	    select undef, undef, undef, 0.5;
	    if ($um->processRuns() == 0)
	    {
		last;
	    }
	    else
	    {
		$prLog->print('-kind' => 'D',
			      '-str' => ["waiting for umount command ..."])
		    if $debug;
	    }
	}
	$um->DESTROY();
	if ($um->get('-what' => 'status') != 0)    # umount not successfull
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["could not <umount $m>"]);
	    $um->signal('-value' => 9);
	    $main::exit |= 2;
	}
	else
	{
	    $prLog->print('-kind' => 'I',
			  '-str' => ["<umount> $m successfull"]);
	}
    }
}
