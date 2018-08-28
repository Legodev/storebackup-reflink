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


# $0 comprProg fileToRead fileToSave md5RetFile
# ret:
#   0 ok
#   1 cannot open fileToRead
#   2 cannot exec comprProg
#   3 cannot write md5sum


my ($fileToRead, $fileToSave, $md5RetFile) = @ARGV;


unless (sysopen(IN, $fileToRead, O_RDONLY))
{
    print STDERR "cannot open <$fileToRead> (", __FILE__, " ", __LINE__,  ")\n";
    exit 1;
}

unless (sysopen(OUT, $fileToSave, O_CREAT|O_WRONLY, 0700))
{
    print STDERR "cannot open <$fileToSave> (", __FILE__, " ", __LINE__,  ")\n";
    exit 2;
}

my $md5 = Digest::MD5->new();
my ($buffer, $n, $size);
$size = 0;
while ($n = sysread(IN, $buffer, 4096))
{
    print STDERR "cannot write to <$fileToSave>\n"
	unless syswrite OUT, $buffer;
    $md5->add($buffer);
    $size += $n;
}
close(OUT);
close(IN);

open(MD5, '>', $md5RetFile)
    or exit 3;
print MD5 $md5->hexdigest(), "\n$size\n";
close(MD5);

exit 0;
