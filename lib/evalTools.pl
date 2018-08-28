# -*- perl -*-

#
#   Copyright (C) Heinz-Josef Claes (2004-2014)
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


push @VERSION, '$Id: evalTools.pl 362 2012-01-28 22:11:13Z hjc $ ';

use strict;

require 'checkObjPar.pl';
require 'fileDir.pl';
require 'prLog.pl';


############################################################
package evalTools;

# create object and prepare data
sub new
{
    my $class = shift;
    my $self = {};

    # set default values for parameters
    my (%params) = ('-linevector'  => [],
		    '-allowedVars' => [],
		    '-tmpdir'      => '/tmp',
		    '-prefix'      => '',     # for log messages
		    '-prLog'       => undef
	);

    &::checkObjectParams(\%params, \@_, 'evalTools::new',
			 ['-linevector', '-allowedVars', '-prLog']);
    &::setParamsDirect($self, \%params);

    my $prLog = $self->{'prLog'};
    my $linevector = $self->{'linevector'};
    $self->{'line'} = join(' ', @$linevector);
    my $allowedVars = $self->{'allowedVars'};
    $self->{'noAllowedVars'} = scalar @$allowedVars;

    my (%allowedVars);        # generate a replacement Table
    $self->{'allowedVars'} = \%allowedVars;
    my ($v, $i);
    $i = 0;
    foreach $v (@$allowedVars)
    {
	$allowedVars{$v} = $i;
	$i++;
    }

    my (%notPattern) = ('(' => undef,
			')' => undef,
			'and' => undef,
			'or' => undef,
			'not' => undef);


    my ($j, $lastEval, %noEval, @debugLinevector);
    for ($i = $j = 0, $lastEval = 1 ; $i < @$linevector ; $i++)
    {
	my $v = $$linevector[$i];
	next if $v =~ /\A\s*\Z/;

	if (exists $notPattern{$v})   # do not evaluate
	{
	    ++$j if $lastEval == 0;

	    $debugLinevector[$j] = $v;
	    $noEval{$v} = $j++;
	    $lastEval = 1;
	}
	else
	{
	    my $a;
	    foreach $a (keys %allowedVars)
	    {
		$v =~ s/\$$a\b/\$_____\[$allowedVars{$a}\]/g;
	    }
	    $debugLinevector[$j] .= ' ' if length($debugLinevector[$j]);
	    $debugLinevector[$j] .= $v;
	    $lastEval = 0;
	}
    }

    if (0)
    {
	my $l;
	print "MAPPING:\n";
	foreach $l (sort keys %allowedVars)
	{
	    print "\t\$$l -> ", $allowedVars{$l}, "\n";
	}
	print "EVAL: ", $self->{'line'}, "\n";
	my $j = 0;
	foreach $l (@debugLinevector)
	{
	    if (exists $noEval{$l})
	    {
		print "\t$j\t-\t$l\n";
	    }
	    else
	    {
		print "\t$j\teval:\t$l\t\t$v\n";
	    }
	    $j++;
	}
    }

    $self->{'noEval'} = \%noEval;
    $self->{'debugLinevector'} = \@debugLinevector;
    $self->{'debugLine'} = join(' ', @debugLinevector);

    $self->{'funcPointer'} = undef;

    bless $self, $class;
}


############################################################
sub fastEval
{
    my $self = shift;
    my $values = shift;

    my $allowedVars = $self->{'allowedVars'};
    my $prLog = $self->{'prLog'};

    unless ($self->{'funcPointer'})
    {
	$self =~ /\((.+)\)/;
	my $id = $1;
	my $tmpfile = &::uniqFileName($self->{'tmpdir'} . '/eval-');
	local *FILE;
	open(FILE, "> $tmpfile") or
	    $prLog->print('-kind' => 'E',
			  '-str' => [$self->{'prefix'} ."cannot open <$tmpfile>"],
			  '-add' => [__FILE__, __LINE__],
			  '-exit' => 1);
	my $funcName = "::EVAL$id";
	print FILE "sub $funcName\n\{\n",
	'my (@_____) = (@_);', "\nreturn (", $self->{'debugLine'}, ");\n\}\n1\n";
	close(FILE);
	require $tmpfile;
	unlink $tmpfile;
	$self->{'funcPointer'} = \&$funcName;
    }

    # set values
    my (@par);
    my ($k, $v);
    while (($k, $v) = each %$values)
    {
	if (exists $$allowedVars{$k})
	{
	    $par[$$allowedVars{$k}] = $v;
	}
	else
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => [$self->{'prefix'} .
				     "unknown variable <$k> for",
				     "<" . $self->{'line'} . ">"],
			  '-exit' => 1);
	}
    }

    my $funcPointer = $self->{'funcPointer'};
    return &$funcPointer(@par) ? 1 : 0;
}

############################################################
sub checkLineDebug
{
    my $self = shift;
    my $values = shift;    # hash with values for allowedVars
    my $secondPrefix = shift;

    my $prLog = $self->{'prLog'};
    my $noEval = $self->{'noEval'};
    my $debugLinevector = $self->{'debugLinevector'};
    my $allowedVars = $self->{'allowedVars'};
    my $prefix = $self->{'prefix'};
    # set values
    my (@_____);
    my ($k, $v);
    while (($k, $v) = each %$values)
    {
	if (exists $$allowedVars{$k})
	{
	    $_____[$$allowedVars{$k}] = $v;
	}
	else
	{
	    $prLog->print('-kind' => 'E',
			  '-str' => ["${prefix}unknown variable <$k> for",
				     "<" . $self->{'line'} . ">"],
			  '-exit' => 1);
	}
    }

    my ($l, @realVal, @ret);
    foreach $l (@$debugLinevector)
    {
	my $lorig = $l;

	my ($k, $v, $realVal);
	$realVal = $l;
	while (($k, $v) = each %$allowedVars)
	{
	    $realVal =~ s/\$_____\[$v\]/$$values{$k}/g;
	}
	push @realVal, $realVal;
#print "++ <$lorig> ++ <$l> ++ <$realVal> ++\n";

	if (exists $$noEval{$lorig})   # the ones to eval
	{
	    push @ret, -1;
	}
	else
	{
	    push @ret, eval $l ? 1 : 0;
	}
    }

    my ($i, @l, @r);
    for ($i = 0 ; $i < @$debugLinevector ; $i++)
    {
	my $d = $realVal[$i];
	push @l, $d;
	my $space = ' ' x (length($d) - 1);
	push @r, $ret[$i] == -1 ? $d : $space . $ret[$i];
    }
    my $ret = eval $self->{'debugLine'} ? 1 : 0;
    $prLog->print('-kind' => 'D',
		  '-str' => ["$prefix$secondPrefix" . join(' ', @l),
			     ' ' x length("$prefix$secondPrefix") . join(' ', @r) .
		  "  ==> $ret"]);
    return $ret;
}


############################################################
sub checkLineBug
{
    my $self = shift;

    # set default values for parameters
    my (%params) = ('-exitOnError'  => undef,  # error code
		    '-printError' => undef
	);

    &::checkObjectParams(\%params, \@_, 'evalTools::checkLineBug', []);

    my (@_____);
    foreach (1..$self->{'noAllowedVars'})
    {
	push @_____, 0;
    }

    my $line = $self->{'debugLine'};
#    print "line = <$line>\n";

    eval $line;
    if ($@)
    {
	$self->{'prLog'}->print('-kind' => 'E',
				'-str' =>
				[$self->{'prefix'} .
				 "syntax error checking <" . $self->{'line'} .
				 '>', $@,
				 "(Hint: always mask '(', ')', '/' " .
				 "and reserved words)"])
	    if $params{'-printError'};
	exit $params{'-exitOnError'} if $params{'-exitOnError'};
	return 1;
    }

    return 0;
}


############################################################
sub getEvalLine
{
    my $self = shift;

    return $self->{'line'};
}

1
