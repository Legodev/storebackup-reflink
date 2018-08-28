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


######################################################################
# usage of CheckParam
# Checks command line options and parameters. These options can also be
# read from a configuration file.
#
# General usage:
#my $Help = <<EOH;
#usage
#    $0 -f configFile ....
#EOH
#    ;
#my $CheckPar =
#    CheckParam->new('-configFile' => '-f',   # optional
#		    .... other params
#		    '-list' => [Option->new('-name' => 'confFile',
#					    '-cl_opton' => '-f',
#					    '-cf_key' => 'configFile',
#					    '-must_be' => 'yes',
#					    '-param' => 'yes',
#					    .... other params
#					    ),
#				Option->new('-name' => 'verbose',
#                                           .... descrition of next option
#				);
#		    ]
#    );
#$CheckPar->check('-argv' => \@ARGV,
#                 '-help' => $Help,
#                 );
#my (@optNames) = $CheckPar->getOptNamesSet('-type' => 'withPar');
#my (@optNames) = $CheckPar->getOptNamesSet('-type' => 'withoutPar');
#my $configFile = $CheckPar->getOptWithPar('confFile');
#my $verbose = $CheckPar->getOptWithoutPar('verbose');
#$CheckPar->print();
#my (@list) = $CheckPar->getListPar();
#my numberListPar = $CheckPar->getNoListPar();
#my (@list) = $CheckPar->getOptOrder();
#
######################################################################
# Options of Option::new
#
# '-name'        Gives this option a unique name. This is the only option which
#                *must* be set.
#
# '-cl_option'   Specify if this option can be set via command line, eg. '-v'
#                Must be set if you want to be able to use command line.
# '-cl_alias'    Optionally, define an alias for '-cl_option', eg. '--verbose'
#
# '-cf_key'      Specify if this option can be set in configuration
#                file, 'verbose'
# '-cf_noOptSet' This option must be set, if '-param' => 'no':
#                (command line option without parameter) to use this
#                option in a configuration file.
#                Defines, how such a parameter (flag) can be set or unset,
#                eg.: ['yes', 'no'] which means 'yes' is equal to set the
#                parameter at command line. If not set in configuration file,
#                the result is the same as not to set at command line.
#                If set to 'yes', result is 1. If set to 'no', result is undef.
# '-multiple'    Must be 'yes' or 'no' (default). If 'no', only one value can
#                be specified. If 'yes', you can assign multiple values.
#                On command line: use the same option multiple times, eg.
#                                -p 1 -p 2 -p 3  (assigenes 3 values 1, 2, 3)
#                You can use the `magic' '--', where all parameters are filtered
#                with the same algorithm as in the configuration file.
#                In fact, this makes -multiple to -quoteEval:
#                                -p -- '1 2 3'   (assigenes 3 values 1, 2, 3)
#                      or use    -p -- "'1 2' 3" (assigenes 2 values '1 2', 3)
#                      or use    -p -- "\"1 2\" 3"(assigenes 2 values '1 2', 3)
#                In config file:  assign multiple values, eg.
#                                 prior = 1 2 3
#                '-multiple' also sets '-param' equal to 'yes'
# '-quoteEval'   Must be 'yes' or 'no'
#                Automatic quote evaluation for cl
#                useful for eg: 'gzip -d' on cl
#                only allowed, when '-multiple' => 'no'
#                for cf, '-multiple' is set automatically
#                for cl multiple arguments are not allowed
#                -params is automatically set to 'yes'
# '-param'       Must be set if the option has a value to assign to via command
#                line or configuration file (see also '-default' and '-multiple').
#                Can be set to 'yes' or 'no' (default).
# '-default'     Spezifies a default parameter for an option.
#                If '-multiple' => 'no', a scalar, eg. 'value'.
#                If '-multiple' => 'yes', a pointer to a field, eg. '['v1, 'v2']
#                Option '-param' is set automatically.
# '-priority'    'cl' or 'cf'. Command line (cl) or configuration file (cf)
#                overwrites the other one. Default is 'cl'.
# '-must_be'     'yes' or 'no' (default). If set to 'yes', method 'check' of
#                object CheckParam will generate an error message if this
#                Option is not set.
# '-only_if'     You can specify a rule which must be fulfilled if this option
#                is choosen. If not, an error message is generated (see also
#                '-comment'). Example:
#                '[configFile] and [verbose]' means, that the options
#                whith the names ('-name') configFile and verbose *must* be set
#                to be allowed to set this option.
#                A rule is any combination of 'and', 'or', 'exor', '(', ')'.
#                The names (-name) of the options must be set in square brackts,
#                 eg. [nameOfOption]. Example of a rule:
#                '[a] or ( [b] and [c] ) or ( [d] and not [a] )'
#                [a], [b], etc. are names of options. The are replaced with
#                one, if the option is set, and with zero if not. If the
#                result of the boolean rule is zero, an error message is generated.
# '-pattern'     You can specifay a pattern against all parameters for the option
#                will be tested. Generates an error message if this failes.
#                (see also '-comment'). Example:
#                '\A\d+\Z' which allows only positive numbers.
#                If you are using '-multiple', the pattern is checked
#                for each parameter of the option.
#                If you are using '-quoteEval', each parameter is checked
#                *after* evaluating the parameter.
# '-comment'     If specified, this text will be printed instead of an
#                automatically generated messages if '-pattern' or '-only_if'
#                fails.
# '-hidden'      Option not shown with CheckParam::print
#                values: 'yes', 'no'. Default = 'no'
#
######################################################################
# Parameters of CheckParam::new
#
# '-list'        Contains a pointer to a list of pointers to class Option
#                (see example above).
# '-configFile'  Specifies the option used at command line for the configuration
#                file: '-cl_option' of that option (*not* '-name').
# '-allowLists'  Specifies, if 'list' parameters like '*.h' without a special
#                option are allowed on command line (see also next option).
# '-listMapping' Specifies the name ('-name') of an option which is mapped
#                to the list parameter (like '*.h*' above).
#                ('-priority' also is relevant here.)
#                Use this only if you use a configuration file.
#                The option pointed to must only have '-cf_key', not
#                '-cl_option' or '-cl_alias'.
# '-replaceEnvVar' 'yes' (default) or 'no'. Default is to replace
#                environment variables (beginning with $, eg. $PWD)
# '-ignoreLeadingWhiteSpace' If set to 1, ignore leading white spaces
#                for options in configuration file. Default is undef.
#                -> this means, that no continuation of a line in the
#                -> next line is possible!
#
######################################################################
# Options of CheckParam::check
#
# '-argv'        Pointer to argument vector of skript, eg. \@ARGV
# '-help'        Help text which will be written in case of an error
# '-ignoreAdditionalKeys' If set to 1, do not generate an error message
#                when keys are found, which are not described with
#                Option objects. Useful when reading configuration
#                files only partially. Default is undef.
#
######################################################################
# Options of CheckParam::getOptWithPar
#
# simply the name of the option to ask for
# return value is a scalar or a field, depending on '-multiple'
#
######################################################################
# Options of CheckParam::getOptWithoutPar
#
# simply the name of the option to ask for
# return value is undef or 1
#
######################################################################
# Options of CheckParam::print
#
# '-showHidden'   also show options with the '-hidden' flag
#
######################################################################
# special options for command line
# --              If the parameter of list option begins with '-',
#                 you have to mask it with '--', eg. instead of '-abc'
#                 you have to write '-- -abc' at the command line.
# --unset         If you want to unset an option which is set in the
#                 configuration file on the command line (not
#                 overwriting, simply unsetting it), the following
#                 syntax is available on the command line:
#                 '--unset <identifiert> where identifier is the
#                 value defined by '-cl_option', '-cl_alias' or '-cf_key'.
#                 if you want to unset an option in the configuration
#                 file, simply write:
#                 identifier =
#                 It is only possible to unset a value if '-must_be'
#                 equals to 'no' and '-priority' equals to 'cl'.
#
######################################################################
# syntax of configuration files
#
# You can set an option specified with '-cf_key' (eg. logFiles) and
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
# If you want to unset an option (also not the default value, no value at all):
# logFILE = [[undef]]
# You can also use environment variables, like $XXX or ${XXX} like in
# a shell script. Single quotes will mask environment variables, while double
# quotes will not.
# You can mask $, {, }, ", ' with a backslash (\), eg. \$
# Lines beginning with a '#' are ignored (use this for comments)



use strict;

require 'checkObjPar.pl';
######################################################################
# Speicherung s"amtlicher Informationen "uber *einen* Parameter
package Option;

sub new
{
    my ($class) = shift;
    my ($self) = {};

    # Defaultwerte f"ur Parameter setzen
    my (%params) = (
	    '-name' => undef,

            # command line options
            '-cl_option' => undef,
	    '-cl_alias' => undef,

            # configuration file options
            '-cf_key' => undef,
            '-cf_noOptSet' => undef, # must be set, when '-param' => 'no'
	                             # eg. ['yes', 'no'] which means
	                             # 'yes' in config file is equal to set
	                             # the parameter at command line
	                             # if not set in config file, same as not
	                             # not set at command line

            # options for command line and configuration files
	    '-default' => undef,
	    '-param' => 'no',    # wird gesetzt, wenn '-default'
            '-priority' => 'cl', # valid options are 'cl' or 'cf'
	                         # default is 'cl': command line overwrites
	                         # configuration file
	    '-only_if' => undef,
	    '-must_be' => 'no',
            '-multiple' => 'no',
	    '-quoteEval' => 'no',  # automatic quote evaluation for cl
	                           # useful for eq: 'gzip -d' on cl
	                           # only allowed, when '-multiple' => 'no'
	                           # for cf, '-multiple' is set automatically
	                           # -params is automatically set to 'yes'
	    '-comment' => undef,   # will be printed if there is something
	                           # wrong found at -only_if and -pattern
	    '-pattern' => undef,   # allow only this pattern
	    '-hidden' => 'no'      # option not shown with CheckParam::print
	    );

    &::checkObjectParams(\%params, \@_, 'Option::new', ['-name']);

    if (defined($params{'-default'}) and $params{'-multiple'} eq 'yes')
    {
	my (@d) = (@{$params{'-default'}});     # make a copy, don't work
	$params{'-default'} = \@d;              # with references because of
    }	                                        # side effects
    $params{'-param'} = 'yes' if defined($params{'-default'})
	or $params{'-multiple'} eq 'yes';
    $params{'-used'} = 'no';   # wird in CheckParam::check dann "uberpr"uft

    die "--unset is reserved. You cannot use it with -cl_option, ",
    "-cl_alias or -cf_key in Option ", $params{'-name'}
	if $params{'-cl_option'} eq '--unset' or $params{'-cl_alias'}
        eq '--unset' or $params{'-cf_key'} eq '--unset';

    if ($params{'-param'} eq 'no' and defined($params{'-cf_key'}))
    {
	if (defined($params{'-cf_noOptSet'}))
	{
	    die "-cf_noOptSet for option <", $params{'-name'},
	    "> must define excatly two values"
		unless ref($params{'-cf_noOptSet'}) eq 'ARRAY' and
		@{$params{'-cf_noOptSet'}} == 2;
	}
	else
	{
	    die "missing definition of '-cf_noOptSet' for option <",
	    $params{'-name'}, ">"
		if $params{'-quoteEval'} eq 'no'
	}
    }

    die "-multiple must be 'yes' or 'no' in option <", $params{'-name'}, ">"
	unless $params{'-multiple'} =~ /\Ayes\Z|\Ano\Z/;

    die "-priority must be 'cl' or 'cf' in option <", $params{'-name'}, ">"
	unless $params{'-priority'} =~ /\Acl\Z|\Acf\Z/;

    # -quoteEval uses algorithm of -multiple (and is the same for cf)
    die "-multiple must be 'no' if -quoteEval is yes"
	if $params{'-quoteEval'} eq 'yes' and $params{'-multiple'} eq 'yes';
    if ($params{'-quoteEval'} eq 'yes')
    {
	$params{'-multiple'} = 'yes';
	$params{'-param'} = 'yes';
    }

    $self->{'param'} = \%params;    # Parameter an Objekt binden

    bless($self, $class);
}


sub get
{
    my ($self) = shift;
    my ($par) = shift;

    return $self->{'param'}{$par};
}


sub set
{
    my ($self) = shift;
    my ($par) = shift;
    my ($val) = shift;

    $self->{'param'}{$par} = $val;
}

######################################################################
package ConfigFile;

sub new
{
    my ($class) = shift;
    my ($self) = {};

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-file' => undef,
		    '-replaceEnvVar' => 'yes',
		    '-ignoreLeadingWhiteSpace' => undef
	);

    &::checkObjectParams(\%params, \@_, 'ConfigFile::new',
			 ['-file']);
    &::setParamsDirect($self, \%params);
    bless $self, $class;

    die "replaceEnvVar must be 'yes' or 'no' in ConfigFile::new"
	unless $self->{'replaceEnvVar'} =~ /\Ayes\Z|\Ano\Z/;
    my $ignoreLeadingWhiteSpace = $self->{'ignoreLeadingWhiteSpace'};

    # read config file
    my $file = $self->{'file'};
    local *FILE;
    if ($file =~ /\.bz2\Z/)
    {
	open(FILE, "bzip2 -d < \'$file\' |") or
	    die "cannot open configuration file <$file>";
    }
    elsif ($file =~ /\.gz\Z/)
    {
	open(FILE, "gzip -d < \'$file\' |") or
	    die "cannot open configuration file <$file>";
    }
    else
    {
	open(FILE, $file) or die "cannot open configuration file <$file>";
    }
    my (@configFile) = <FILE>;
    chomp @configFile;
    close(FILE);

    # identify keys
    my (%keys, $l);
    my (@cf) = (@configFile);       # working copy of @configFile
    $self->{'keys'} = \%keys;
    my $actKey = undef;
    my $i = 0;
    foreach $l (@cf)
    {
	$i++;
	$l =~ s/\A\s+(.*?)\Z/$1/
	    if $ignoreLeadingWhiteSpace;

	if ($l =~ /\A[#;]/ or $l =~ /\A\s*\Z/)  # comment or empty
	{
	    $actKey = undef;
	    next;
	}
	if ($l =~ /\A\s+/)
	{
	    die "continue line with no key at line $i:\n<",
	    $configFile[$i-1], ">\n" unless $actKey;

	    $keys{$actKey}{'line'} .= ' ' . $l;
	}
	else
	{
	    if ($l =~ /\A(.+?)\s*=\s*(.*)\Z/)
	    {
		$actKey = $1;
		$keys{$actKey}{'line'} = $2;
		$keys{$actKey}{'lineno'} = $i;
	    }
	    else
	    {
		die "cannot identify line $i in file $file:\n<",
		$configFile[$i-1], ">\n";
	    }
	}
    }

#    print "---------- analyzed keys\n";
    # analyse lines of keys
    foreach $actKey (keys %keys)
    {
	$l = $keys{$actKey}{'line'};
	my $v = splitQuotedLine($l, "in configuration file at line " .
				$keys{$actKey}{'lineno'},
				$self->{'replaceEnvVar'} eq 'no');
	if (@$v)
	{
	    $keys{$actKey}{'parts'} = $v;
	}
	else
	{
	    delete $keys{$actKey};   # value is not set in config file
	}
    }

    return $self;
}

########################################
sub splitQuotedLine
{
    my $l = shift;
    my $errorPart = shift;   # where this happens, 'in file at ...'
    my $doNotReplaceEnvVar = shift;   # 1 or undef

    $doNotReplaceEnvVar = 0 unless defined $doNotReplaceEnvVar;

    # masking of special characters
    my $dollar = "\001";  # mask for \$
    my $ob = "\002";      # open bracket: mask for \{
    my $cb = "\003";      # close bracket: mask for \{
    my $sq = "\004";      # single quote: \'
    my $dq = "\005";      # double quote \"

    $l =~ s/\\\$/$dollar/g;# replace \$ with $dollar
    $l =~ s/\\\{/$ob/g;    # replace \{ with $ob
    $l =~ s/\\\}/$cb/g;    # replace \} with $cb
    $l =~ s/\\\'/$sq/g;    # replace \' with $sq
    $l =~ s/\\\"/$dq/g;    # replace \" with $dq

    my (@l);
#print "l = <$l>, doNotReplaceEnvVar = <$doNotReplaceEnvVar>\n";
    while (length($l))
    {
	$l =~ s/\A\s*(.*?)\s*\Z/$1/;   # remove leading and trailing \s
	my $sQuote = index($l, '\'');
	my $dQuote = index($l, '"');
#print "sQuote = $sQuote\n";
#print "dQuote = $dQuote\n";
	if ($sQuote == -1 and $dQuote == -1)   # no quotes
	{
	    push @l, replaceEnvironmentVars($doNotReplaceEnvVar,
					    $errorPart,
					    split(/\s+/, $l));
	    $l = '';
	}
	elsif ($dQuote == -1 or
	       ($sQuote != -1 and $sQuote < $dQuote))  # single quote
	{
#print "-1- <$l>\n";
	    if ($l =~ /\A(.*?)\'(.*?)\'(.*)\Z/)
	    {
		push @l, replaceEnvironmentVars($doNotReplaceEnvVar,
						$errorPart,
						split(/\s+/, $1));
		push @l, $2;
		$l = $3;
#print "\t<", join('> <', @l), "> + <$l>\n";
	    }
	    else
	    {
		die "missing \' $errorPart:\n<$l>\n";
	    }
	}
	else              # double quote
	{
#print "-2- <$l>\n";
	    if ($l =~ /\A(.*?)\"(.*?)\"(.*)\Z/)
	    {
		push @l, replaceEnvironmentVars($doNotReplaceEnvVar,
						$errorPart,
						split(/\s+/, $1));
		push @l, replaceEnvironmentVars($doNotReplaceEnvVar,
						$errorPart, $2);
#print "\t<", join('> <', @l), "> + <$l>\n";
		$l = $3;
	    }
	    else
	    {
		die "missing \" $errorPart:\n<$l>\n";
	    }
	}
    }

    my $i;                # remask special characters
    for ($i = 0 ; $i < @l ; $i++)
    {
	$l[$i] =~ s/$dollar/\$/g;
	$l[$i] =~ s/$ob/\{/g;
	$l[$i] =~ s/$cb/\}/g;
	$l[$i] =~ s/$sq/\'/g;
	$l[$i] =~ s/$dq/\"/g;
    }

#print "-3- \@l = <", join('><', @l), ">\n";
    return \@l;
}


########################################
sub replaceEnvironmentVars
{
    my ($doNotReplaceEnvVar, $errorPart, @lines) = @_;

    return (@lines) if $doNotReplaceEnvVar;

    my (@newLines);
    my $l;
    foreach $l (@lines)
    {
	while (1)
	{
	    my $env = index($l, "\$");
	    if ($env < 0)
	    {
		push @newLines, $l;
		last;
	    }
	    else
	    {
		my $env;
		if ($l =~ /\$\{(\w+)\}/)
		{
		    $env = $1;
		}
		else
		{
		    $l =~ /\$(\w+)\W*/;
		    $env = $1;
		}

		die "environment variable \$$env not set\n",
		"please set \$$env before calling this program $errorPart"
		    unless $ENV{$env};

		$l =~ s/\$\{?$env\}?/$ENV{$env}/;
	    }
	}
    }

    return (@newLines);
}


########################################
sub getKeysPointer
{
    my $self = shift;

    return $self->{'keys'};
}


######################################################################
package CheckParam;

sub new
{
    my ($class) = shift;
    my ($self) = {};

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-list' => [],
		    '-configFile' => undef,
		    '-allowLists' => 'no',
		    '-listMapping' => undef,
		    '-replaceEnvVar' => 'yes',
		    '-ignoreLeadingWhiteSpace' => undef);

    $params{'-allowLists'} = 'yes'
	if defined $params{'-listMapping'};

    &::checkObjectParams(\%params, \@_, 'CheckParam::new', []);

    $self->{'paramList'} = \%params;    # Parameter an Objekt binden
    $self->{'listMapping'} = $params{'-listMapping'};

    # Hash mit '-cl_option' und '-cl_alias' f"ur schnellen Zugriff auf Option
    # Hash mit '-cf_key' f"ur schnellen Zugriff auf Option
    my (%option, %key, %name, %n, $o);
    foreach $o (@{$self->{'paramList'}{'-list'}})
    {
	my $n = $o->get('-name');
	die "option name <$n> used twice" if exists $n{$n};
	$n{$n} = 1;
	my $opt = undef;
	if ($opt = $o->get('-cl_option'))
	{
	    die "cl_option <$opt> used twice!" if exists $option{$opt};
	    $option{$opt} = $o;
	    my $name = $o->get('-name');
	    $name{$n} = $o;
	}
	if ($opt = $o->get('-cl_alias'))
	{
	    die "cl_option <$opt> used twice!" if exists $option{$opt};
	    $option{$opt} = $o;
	    $name{$n} = $o;
	}
	if ($opt = $o->get('-cf_key'))
	{
	    die "cf_key <$opt> used twice!" if exists $key{$opt};
	    $key{$opt} = $o;
	    $name{$n} = $o;
	}
    }
    $self->{'optionsPointer'} = \%option;
    $self->{'keysPointer'} = \%key;
    $self->{'namePointer'} = \%name;

    bless($self, $class);
}


sub getList
{
    my ($self) = shift;
    my ($par) = shift;

    return $self->{'paramList'}{$par};
}


sub check
{
    my ($self) = shift;
    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-argv' => [[]],
		    '-help' => ['<noHelp>'],
		    '-ignoreAdditionalKeys' => undef);

    my $replaceEnvVar =
	$self->{'paramList'}{'-replaceEnvVar'};
    my (%hash) = @_;    # Parameter in Hash kopieren
    my ($k);
    foreach $k (keys %params)
    {
	if (defined($hash{$k}))
	{
	    $params{$k} = $hash{$k};  # Wert "uberschreiben
	    delete $hash{$k};
	}
	else
	{
	    $params{$k} = $params{$k}[0];  # Defaultwert einsetzen
	}
    }
    my ($Help) = $params{'-help'};
    die "undefined params <", join('><', keys %hash),
    "> in CheckParam::check\n"
	if (keys %hash > 0);

    # Die gesetzten Optionen erst einmal auf Parameter analysieren
    my $op = $self->{'optionsPointer'};
    my ($configFile, $configFileParam) = (undef, undef);
    if (defined $self->{'paramList'}{'-configFile'})
    {
	$configFileParam = $self->{'paramList'}{'-configFile'};
	die "CheckParam::configFile option <$configFileParam> does not exist"
	    unless exists $op->{$configFileParam};
    }

    my ($arg, @parList, $next, $aktOpt, %optWithPar,
	@optOrder, %optWithoutPar, %unset, $i);

    # Ergebnisse merken
    $self->{'Erg'}{'withPar'} = \%optWithPar;
    $self->{'Erg'}{'withoutPar'} = \%optWithoutPar;
    $self->{'Erg'}{'listPar'} = \@parList;
    $self->{'Erg'}{'optOrder'} = \@optOrder;

    $next = 'unknown';
    my $i;
    for ($i = 0 ; $i < @{$params{'-argv'}} ; $i++)
    {
	$arg = $params{'-argv'}[$i];

	if ($next eq 'list')  # Listenparameter
	{
	    push @parList, $arg;
	    $next = 'unknown';
	    next;
	}
	if ($next eq 'unset')
	{
	    $unset{$arg} = 1;
	    $next = 'unknown';
	    next;
	}
	if ($arg eq '--')   # n"achster Parameter ist 'list' - Parameter
	{
	    die "missing list parameter after '--'"
		if $i + 1 >= @{$params{'-argv'}};
	    $next = 'list';
	    next;
	}
	if ($arg eq '--unset')
	{
	    die "missing list parameter after '--unset'"
		if $i + 1 >= @{$params{'-argv'}};
	    $next = 'unset';
	    next;
	}
	if (defined($op->{$arg}))   # bekannte Option
	{
	    my $o = $op->{$arg};
	    $arg = $o->get('-cl_option');
	    $o->set('-used' => 'yes');
	    my $name = $o->get('-name');
	    push @optOrder, $name;

	    if ($o->get('-param') eq 'yes')
	    {
		$optWithPar{$name}{'object'} = $o;
		die "missing param for option <$arg>\n$Help"
		    if (++$i >= @{$params{'-argv'}});
		if ($o->get('-multiple') eq 'yes')
		{
		    die "Parameter $arg is used for setting the configuration" .
			" file. It cannot be used with -multiple => yes"
			if $arg eq $configFileParam;
		    my $l = $params{'-argv'}[$i];
		    if ($l eq '--')
		    {
			die "missing param for option <$arg>\n$Help"
			    if (++$i >= @{$params{'-argv'}});
			$l = $params{'-argv'}[$i];
			push @{$optWithPar{$name}{'value'}},
			@{ConfigFile::splitQuotedLine($l, "at <$arg>",
			  $replaceEnvVar eq 'no')};
		    }
		    else
		    {
			if ($o->get('-quoteEval') eq 'yes')
			{
			    die "cannot use $arg multiple times\n$Help",
				if defined $optWithPar{$name}{'value'};

			    $l = $params{'-argv'}[$i];
			    $optWithPar{$name}{'value'} = ();
			    push @{$optWithPar{$name}{'value'}},
			    @{ConfigFile::splitQuotedLine($l, "at <$arg>",
			      $replaceEnvVar eq 'no')};
			}
			else
			{
			    push @{$optWithPar{$name}{'value'}}, $l;
			}
		    }
		}
		else    # '-multiple' eq 'no'
		{
		    if (defined $optWithPar{$name}{'value'})
		    {
			die "parameter $arg defined multiple times with\n<",
			$optWithPar{$name}{'value'}, "> <", $params{'-argv'}[$i],
			">\nit is not possible to have multiple instances" .
			    " of this parameter\n$Help";
		    }
		    else
		    {
			$optWithPar{$name}{'value'} = $params{'-argv'}[$i];
			$configFile = $params{'-argv'}[$i]
			    if $arg eq $configFileParam;
		    }
		}
		next;
	    }
	    else        # keine Parameter an Option
	    {
		$optWithoutPar{$name} = 1;
		next;
	    }
	}
	else      # Listenparameter
	{
	    die "unknown parameter <$arg>\n$Help" if ($arg =~ /^-/);
	    push @parList, $arg;
	    next;
	}
    }

    # %optWithPar enth"alt jetzt die in ARGV gesetzten Optionen mit Parameter
    # $optWithPar{option}{'object'} = Zeiger auf vorgegeb. Objekt f"ur d. Opt.
    # $optWithPar{option}{'value'} = Wert der Option in ARGV

    # Ausgabe der gefundenen Optionen
    if (0)
    {
	my ($k);
	print "Ausgabe der gefundenen Command Line Optionen\n";
	print "\tOptionen mit Parameter:\n";
	foreach $k (sort keys %optWithPar)
	{
	    if (ref($optWithPar{$k}{'value'}) eq 'ARRAY')
	    {
		print "\t\t$k\n";
		my $p;
		my $i = 1;
		foreach $p (@{$optWithPar{$k}{'value'}})
		{
		    print "\t\t  ($i)\t<$p>\n";
		    $i++;
		}
	    }
	    else
	    {
		print "\t\t$k\t<", $optWithPar{$k}{'value'}, ">\n";
	    }
	}
	print "\tOptionen ohne Parameter:\n";
	foreach $k (sort keys %optWithoutPar)
	{
	    print "\t\t$k\n";
	}
	if (defined $configFileParam)
	{
	    print "\tconfig file: $configFileParam <$configFile>\n";
	}
	print "\tList-Parameter:\n";
	foreach $k (sort @parList)
	{
	    print "\t\t<$k>\n";
	}
    }

    # load and merge configuration file
    if ($configFile)
    {
	my $cf = ConfigFile->new('-file' => $configFile,
				 '-replaceEnvVar' => $replaceEnvVar,
				 '-ignoreLeadingWhiteSpace' =>
				 $self->{'paramList'}{'-ignoreLeadingWhiteSpace'}
	    );

	my $kp_cf_file = $cf->getKeysPointer();
	my $kp_definition = $self->{'keysPointer'};

	my $fileKey;
	foreach $fileKey (sort keys %$kp_cf_file)
	{
	    if (defined($kp_definition->{$fileKey}))  # test if '-cf_key' is set
	    {
		my $kp = $kp_cf_file->{$fileKey};
#print "++++++++++++\n-1- key: <$fileKey>\n";
#print "-2- lineno: ", $kp->{'lineno'}, "\n";
#print "-3- parts: <",
#join("><", @{$kp->{'parts'}}), ">\n";

		my $k = $kp_definition->{$fileKey};
		my $name = $k->get('-name');
		$optWithPar{$name}{'object'} = $k
		    unless $optWithPar{$name}{'object'};

#print "-5- -cf_key = ", $k->get('-cf_key'), "\n";
#print "-5- -name = ", $name, "\n";
#print "-5- -multiple = ", $k->get('-multiple'), "\n";
#print "-6- -cf_noOptSet = <",
#join("><", @{$k->get('-cf_noOptSet')}), ">\n"
#  if defined $k->get('-cf_noOptSet');

		if (@{$kp->{'parts'}} > 1 and $k->get('-multiple') eq 'no')
		{
		    die "configuration file $configFile, line ",
		    $kp->{'lineno'},
		    ": key <$fileKey> must have only one parameter\n$Help";
		}

		next if $k->get('-priority') eq 'cl' and
		    $k->get('-used') eq 'yes';

		$k->set('-used' => 'yes');

		if ($k->get('-multiple') eq 'yes')
		{
		    my $val = $kp->{'parts'};
		    $val = undef if @$val == 1 and $$val[0] eq '[[undef]]';
		    $optWithPar{$name}{'value'} = $val;
		}
		else           # -muliple eq 'no'
		{
		    if (defined $k->get('-cf_noOptSet'))
		    {
			my ($yes, $no) = (@{$k->get('-cf_noOptSet')});
			my ($val) = (@{$kp->{'parts'}});
			$val = $no unless $val;
			die "configuration file $configFile, line ",
			$kp->{'lineno'},
			": value for key <$fileKey> is <$val>, must be <$yes> or <$no>"
			    if $val ne $yes and $val ne $no;

			$optWithoutPar{$name} =
			    ($val eq $yes) ? 1 : undef;
		    }
		    else
		    {
			my $val = $kp->{'parts'}[0];
			$val = undef if $val eq '[[undef]]';
			($optWithPar{$name}{'value'}) = $val;
		    }
		}
	    }
	    else
	    {
		die "configuration file $configFile, line ",
		$kp_cf_file->{$fileKey}{'lineno'},
		": undefined key <$fileKey>\n$Help"
		    unless $params{'-ignoreAdditionalKeys'};
	    }
	}

    }

    if (0)
    {
	my ($k);
	print "\tOptionen aus Command Line mit Parameter:\n";
	foreach $k (sort keys %optWithPar)
	{
	    if (ref($optWithPar{$k}{'value'}) eq 'ARRAY')
	    {
		print "\t\t$k\n";
		my $p;
		my $i = 1;
		foreach $p (@{$optWithPar{$k}{'value'}})
		{
		    print "\t\t  ($i)\t<$p>\n";
		    $i++;
		}
	    }
	    else
	    {
		print "\t\t$k\t<", $optWithPar{$k}{'value'}, ">\n";
	    }
	}
	print "\tOptionen ohne Parameter:\n";
	foreach $k (sort keys %optWithoutPar)
	{
	    print "\t\t$k\n";
	}
	if (defined $configFileParam)
	{
	    print "\tconfig file: $configFileParam <$configFile>\n";
	}
	print "\tList-Parameter:\n";
	foreach $k (sort @parList)
	{
	    print "\t\t<$k>\n";
	}
    }

    # Überprüfen, ob List-Parameter erlaubt sind
    die "detected the following not allowed list parameters:\n\t<",
    join('> <', @parList), ">\n$Help"
	if (@parList > 0 and $self->{'paramList'}{'-allowLists'} eq 'no');
    # map list parameters
    my $map = $self->{'paramList'}{'-listMapping'};
    if ($map)
    {
	my $o = $self->{'namePointer'}{$map};
	die "-listMapping object <$map> does not exist"
	    unless $o;

	if (defined($optWithPar{$map}) and $optWithPar{$map}{'value'})
	{
	    (@parList) = (@{$optWithPar{$map}{'value'}})
		if $o->get('-priority') eq 'cf' or @parList == 0;
	}
    }

    # Die Defaultwerte einsetzen
    my ($optIter) = IterOpt_CheckParam->new($self);
    my ($o);
    while ($o = $optIter->next())
    {
	next unless (defined $o->get('-default'));  # kein default vorhanden
	my $name = $o->get('-name');
	next if (defined $optWithPar{$name});   # schon in ARGV gesetzt

	$optWithPar{$name}{'object'} = $o;   # auf Default setzen
	$optWithPar{$name}{'value'} = $o->get('-default');
    }

    # check for options to unset (via --unset on command line)
    my $u;
    foreach $u (keys %unset)
    {
	my $o = undef;
	if (defined $self->{'optionsPointer'}{$u})
	{
	    $o = $self->{'optionsPointer'}{$u};
	}
	elsif (defined $self->{'keysPointer'}{$u})
	{
	    $o = $self->{'keysPointer'}{$u};
	}
	die "you tried to --unset option <$u> which is not known\n$Help"
	    unless $o;

	die "cannot unset <$u>, because this option must be set\n$Help"
	    if $o->get('-must_be') eq 'yes';
	die "option <$u> cannot be unmasked from command line\n$Help"
	    if $o->get('-priority') eq 'cf';

	my $name = $o->get('-name');

	if (defined $optWithoutPar{$name})
	{
	    delete $optWithoutPar{$name};
	}
	elsif (defined $optWithPar{$name})
	{
	    delete $optWithPar{$name};
	}
	if ($name eq $map)     # $map = list mapping name
	{
	    @parList = ();     # unset param list also
	}
    }

    # '-must_be' "uberpr"ufen
    while ($o = $optIter->next())
    {
	next if ($o->get('-must_be') eq 'no');  # mu"s nicht sein
	my $name = $o->get('-name');

	if ($o->get('-param') eq 'no')   # kein Parameter
	{
	    die "missing option <$name>\n$Help"
		unless ($optWithoutPar{$name});
	}
	else # hat Parameter
	{
	    die "missing option with parameter <$name param>\n$Help"
		unless ($optWithPar{$name});
	}
    }

    # '-pattern' "uberpr"ufen
    my ($k);
    foreach $k (keys %optWithPar)
    {
	my ($o) = $optWithPar{$k}{'object'};
	next unless ($o->get('-pattern')); # hier gibt's keine Beschr"ankungen
	my ($pat) = $o->get('-pattern');
	if ($o->get('-multiple') eq 'yes')
	{
	    my $v;
	    foreach $v (@{$optWithPar{$k}{'value'}})
	    {
		unless ($v =~ /$pat/)
		{
		    if ($o->get('-comment'))
		    {
			die $o->get('-comment');
		    }
		    else
		    {
			die "<", $v,
			"> is not a valid value for option <$k>\nallowed pattern is ",
			"<$pat>\n$Help";
		    }
		}
	    }
	}
	else
	{
	    unless ($optWithPar{$k}{'value'} =~ /$pat/)
	    {
		if ($o->get('-comment'))
		{
		    die $o->get('-comment');
		}
		else
		{
		    die "<", $optWithPar{$k}{'value'},
		    "> is not a valid value for option <$k>\nallowed pattern is ",
		    "<$pat>\n$Help";
		}
	    }
	}
    }

    # '-only_if' "uberpr"ufen
    while ($o = $optIter->next())
    {
	next unless ($o->get('-only_if'));  # keine Einschr"ankungen
	next if ($o->get('-used') eq 'no'); # Parameter wird nicht verwendet
	my ($only_if) = $o->get('-only_if');

	# zuerst alle gesetzten Parameter durch '1' ersetzen
	my ($k);
	foreach $k (keys %optWithoutPar)
	{
	    $only_if =~ s/\[$k\]/1/g;
	}
	foreach $k (keys %optWithPar)
	{
	    my ($o) = $optWithPar{$k}{'object'};
	    my ($opt) = $o->get('-name');
	    $only_if =~ s/\[$opt\]/1/g;
	}
	$only_if =~ s/\[(.*?)\]/0/g;   # verbliebene durch 0 ersetzen
	my $only_print = $only_if;
	$only_if =~ s/or/\|/g;         # durch bin"are Operatoren ersetzen,
	$only_if =~ s/and/&/g;         # dann funktioniert not (!)
	$only_if =~ s/not/!/g;         # statt '!' kann auch 'not' verw. werden
	$only_if =~ s/exor/^/g;        # statt '^' kann auch 'exor' verw. werd.
	unless (eval "($only_if)")
	{
	    if ($o->get('-comment'))
	    {
		die $o->get('-comment');
	    }
	    else
	    {
		die "illegal combination in use of option <",
		$o->get('-name'), ">, rule = (", $o->get('-only_if'),
		")\n\t\t\t\t\t\t  <<$only_print>>\n$Help";
	    }
	}
    }

    if (0)
    {
	$self->print();
    }
}


########################################
# get names of options which are set
sub getOptNamesSet
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-type' => undef # 'withPar' or 'withoutPar'
	);

    &::checkObjectParams(\%params, \@_, 'CheckParam::getOptNames',
			 ['-type']);

    my $type = $params{'-type'};
    die "type of CheckParam->getOptNames must be withPar or withoutPar"
	unless $type =~ /\AwithPar\Z|\AwithoutPar\Z/;

    my $opts = $self->{'Erg'}{$type};
    return sort keys %$opts;
}


########################################
sub print
{
    my $self = shift;

    # Defaultwerte f"ur Parameter setzen
    my (%params) = ('-showHidden' => 0    # 1 = show hidden
	);

    &::checkObjectParams(\%params, \@_, 'CheckParam::print', []);

    my $optWithPar = $self->{'Erg'}{'withPar'};
    my $optWithoutPar = $self->{'Erg'}{'withoutPar'};
    my $parList = $self->{'Erg'}{'listPar'};

    my ($k);
    print "combined configuration and command line options\n";
    print "\toptions with parameters:\n";
    foreach $k (sort keys %$optWithPar)
    {
	my $hidden = $self->{'namePointer'}{$k}->get('-hidden');
	my $show = $params{'-showHidden'} eq 'yes' || $hidden eq 'no';
	next unless $show;
	if (not defined $optWithPar->{$k}{'value'})
	{
	    print "\t\t$k\t<undef>\n";
	}
	elsif (ref($optWithPar->{$k}{'value'}) eq 'ARRAY')
	{
	    print "\t\t$k\n" if $show;
	    my $p;
	    foreach $p (@{$optWithPar->{$k}{'value'}})
	    {
		print "\t\t\t<$p>\n";
	    }
	}
	else
	{
	    print "\t\t$k\t<", $optWithPar->{$k}{'value'}, ">\n";
	}
    }
    print "\toptions without parameters:\n";
    foreach $k (sort keys %$optWithoutPar)
    {
	my $hidden = $self->{'namePointer'}{$k}->get('-hidden');
	my $show = $params{'-showHidden'} eq 'yes' || $hidden eq 'no';
	print "\t\t$k\n" if $show;
    }
    my $lp = '';
    $lp = ' (' . $self->{'listMapping'} . ')'
	if defined $self->{'listMapping'};
    print "\tlist parameters$lp:\n";
    foreach $k (@$parList)
    {
	print "\t\t<$k>\n";
    }
}

########################################
sub getOptWithPar
{
    my $self = shift;
    my $par = shift;

    die "option <$par> does not exist"
	unless defined $self->{'namePointer'}{$par};
    die "option <$par> does not have a parameter, use getOptWithoutPar"
	unless $self->{'namePointer'}{$par}->get('-param') eq 'yes';

    my $r = $self->{'Erg'}{'withPar'}{$par}{'value'};
    if (ref($r) eq 'ARRAY')
    {
	$r = undef if @$r == 0;
    }
    return $r;
}

########################################
sub getOptWithoutPar
{
    my $self = shift;
    my $par = shift;

    die "option <$par> does not exist"
	unless defined $self->{'namePointer'}{$par};
    die "option <$par> has a parameter, use getOptWithPar"
	unless $self->{'namePointer'}{$par}->get('-param') eq 'no';

    return $self->{'Erg'}{'withoutPar'}{$par};
}

########################################
sub getListPar
{
    my $self = shift;

    return @{$self->{'Erg'}{'listPar'}};
}

########################################
sub getNoListPar
{
    my $self = shift;

    return scalar(@{$self->{'Erg'}{'listPar'}});
}

########################################
# order of options in @ARGV, if one option is used multiple times
# it's also multiple times in the list
sub getOptOrder
{
    my $self = shift;

    return @{$self->{'Erg'}{'optOrder'}};
}


######################################################################
# Iterator f"ur die List-Parameter
package Iter_ParList;

sub new
{
    my ($class) = shift;
    my ($CheckPar) = shift;
    my ($self) = {};

    $self->{'list'} = $CheckPar->{'Erg'}{'listPar'};
    $self->{'index'} = -1;
    bless($self, $class);
}

sub next
{
    my ($self) = shift;
    my ($l) = $self->{'list'};

    ++$self->{'index'};
    if ($self->{'index'} >= @$l)   # Ende erreicht
    {
	$self->{'index'} = -1;
	return undef;
    }
    else
    {
	return $$l[$self->{'index'}];
    }
}

######################################################################
# Iterator f"ur CheckParam, um s"amtliche gespeicherten Option zu erhalten
package IterOpt_CheckParam;

sub new
{
    my ($class) = shift;
    my ($CheckPar) = shift;
    my ($self) = {};

    $self->{'list'} = $CheckPar->getList('-list');
    $self->{'index'} = -1;

    bless($self, $class);
}


sub next
{
    my ($self) = shift;
    my ($l) = $self->{'list'};

    ++$self->{'index'};
    if ($self->{'index'} >= @$l)   # Ende erreicht
    {
	$self->{'index'} = -1;
	return undef;
    }
    else
    {
	return $$l[$self->{'index'}];
    }
}
