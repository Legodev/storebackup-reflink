# -*- perl -*-

#
#   Copyright (C) Heinz-Josef Claes (2002-2014)
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



use strict;


##################################################
sub splitLine
{
    my $line = shift;
    my $length = shift;
    my $pattern = shift;  # separator between words, normally '\s+'
    my $newLine = shift;  # normally "\n" or <undef>

    my (@lines);
    if ($newLine)
    {
	(@lines) = split($newLine, $line);
    }
    else
    {
	(@lines) = ($line);
    }

    my (@ret) = ();
    foreach my $l (@lines)
    {
	push @ret, &::splitOneLine($l, $length, $pattern);
    }
    return @ret;
}


##################################################
sub splitOneLine
{
    my $line = shift;
    my $length = shift;
    my $pattern = shift;  # separator between words, nomally '\s+'

    my @ret;
    while (1)
    {
	if (length($line) <= $length)
	{
	    push @ret, $line;
	    return @ret;
	}
	# line is too long
	my $begin = substr($line, 0, $length);
	$line = substr($line, $length);

	if ($line =~ /^$pattern/)  # if new line starts exactly with pattern
	{
	    push @ret, $begin;
	    $line =~ s/^($pattern)//;   # delete leading blanks or similar
	    next;
	}

	# split $begin
	my ($a, $b) = $begin =~ /^(.*)$pattern(.*)$/;
	if ($a)
	{
	    push @ret, $a;
	    $line = $b . $line;
	}
	else     # the first word is too long, simply split it
	{
	    push @ret, $begin;
	}
    }
}


1
