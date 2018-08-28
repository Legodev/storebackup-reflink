#! /usr/bin/perl

#
#   Copyright (C) Heinz-Josef Claes (2009-2014)
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

use Fcntl;
use Digest::MD5 qw(md5_hex);

use POSIX;
use POSIX ":sys_wait_h";

# $0 comprProg fileToRead fileToSave md5RetFile
# ret:
#   0 ok
#   1 cannot open fileToRead
#   2 cannot exec comprProg
#   3 cannot write md5sum



my ($comprProg, $fileToRead, $fileToSave, $md5RetFile, $tmpdir,
    @comprProgFlags) = @ARGV;


unless (sysopen(IN, $fileToRead, O_RDONLY))
{
    print STDERR "cannot open <$fileToRead> (", __FILE__, " ", __LINE__,  ")\n";
    exit 1;
}

my $prefix = "$tmpdir/stbu-md5Exec-";
my $suffix;
do
{
    $suffix = sprintf '%08x%08x', rand 0xffffffff, rand 0xffffffff;
}
while (-e $prefix . $suffix);
my $stderr = $prefix . $suffix;


local *PARENT;
my $fd = *PARENT;

my $child;
pipe $child, $fd or die "pipe failed: $!";
my $pid = fork();
die "fork() failed: $!" unless defined $pid;
if ($pid == 0) # in the parent
{
    close $Child;
}
elsif ($pid < 0)
{
    die "failed to fork in $0\n";
}
else  # in the child
{
    close PARENT;
    open(STDERR, ">", $stderr)
	or die "cannot open STDERR";
    open(STDIN, "<&=" . fileno($child))
	or die "cannot open STDIN";
    open(STDOUT, ">", $fileToSave)
	or die "cannot open STDOUT";

    exec($comprProg, @comprProgFlags);
    die "couldn't exec $comprProg @comprProgFlags";
}


chmod 0700, $fileToSave;
if (-s $stderr)      # file exists and is > 0
{
    open(ERR, "<", $stderr)
	or print STDERR "cannot open <$stderr> in $0";
    my (@err) = <ERR>;
    close(ERR);
    print STDERR "@err";
}
unlink $stderr;

my $md5 = Digest::MD5->new();
my ($buffer, $n, $size);
$size = 0;
while ($n = sysread(IN, $buffer, 4096))
{
    print STDERR "cannot write to <$fileToSave>\n"
	unless syswrite $fd, $buffer;
    $md5->add($buffer);
    $size += $n;
}
close($fd);
close(IN);
waitpid $pid, 0;

unless (open(MD5, '>', $md5RetFile))
{
    print STDERR "cannot write to <$md5RetFile>\n";
    exit 3;
}
print MD5 $md5->hexdigest(), "\n$size\n";
close(MD5);

exit 0;
