package ExtUtils::MM_Win32;

use strict;
use warnings;


use ExtUtils::MakeMaker::Config;
use File::Basename;
use File::Spec;
use ExtUtils::MakeMaker qw(neatvalue _sprintf562);

require ExtUtils::MM_Any;
require ExtUtils::MM_Unix;
our @ISA = qw( ExtUtils::MM_Any ExtUtils::MM_Unix );
our $VERSION = '7.70';
$VERSION =~ tr/_//d;

$ENV{EMXSHELL} = 'sh'; # to run `commands`

my ( $BORLAND, $GCC, $MSVC ) = _identify_compiler_environment( \%Config );

sub _identify_compiler_environment {
	my ( $config ) = @_;

	my $BORLAND = $config->{cc} =~ /\bbcc/i ? 1 : 0;
	my $GCC     = $config->{cc} =~ /\bgcc\b/i ? 1 : 0;
	my $MSVC    = $config->{cc} =~ /\b(?:cl|icl)/i ? 1 : 0; # MSVC can come as clarm.exe, icl=Intel C

	return ( $BORLAND, $GCC, $MSVC );
}



sub dlsyms {
    my($self,%attribs) = @_;
    return '' if $self->{SKIPHASH}{'dynamic'};
    $self->xs_dlsyms_iterator(\%attribs);
}


sub xs_dlsyms_ext {
    '.def';
}


sub replace_manpage_separator {
    my($self,$man) = @_;
    $man =~ s,[/\\]+,.,g;
    $man;
}



sub maybe_command {
    my($self,$file) = @_;
    my @e = exists($ENV{'PATHEXT'})
          ? split(/;/, $ENV{PATHEXT})
	  : qw(.com .exe .bat .cmd);
    my $e = '';
    for (@e) { $e .= "\Q$_\E|" }
    chop $e;
    # see if file ends in one of the known extensions
    if ($file =~ /($e)$/i) {
	return $file if -e $file;
    }
    else {
	for (@e) {
	    return "$file$_" if -e "$file$_";
	}
    }
    return;
}



sub init_DIRFILESEP {
    my($self) = shift;

    # The ^ makes sure its not interpreted as an escape in nmake
    $self->{DIRFILESEP} = $self->is_make_type('nmake') ? '^\\' :
                          $self->is_make_type('dmake') ? '\\\\' :
                          $self->is_make_type('gmake') ? '/'
                                                       : '\\';
}


sub init_tools {
    my ($self) = @_;

    $self->{NOOP}     ||= 'rem';
    $self->{DEV_NULL} ||= '> NUL';

    $self->{FIXIN}    ||= $self->{PERL_CORE} ?
      "\$(PERLRUN) -I$self->{PERL_SRC}\\cpan\\ExtUtils-PL2Bat\\lib $self->{PERL_SRC}\\win32\\bin\\pl2bat.pl" :
      'pl2bat.bat';

    $self->SUPER::init_tools;

    # Setting SHELL from $Config{sh} can break dmake.  Its ok without it.
    delete $self->{SHELL};

    return;
}



sub init_others {
    my $self = shift;

    $self->{LD}     ||= 'link';
    $self->{AR}     ||= 'lib';

    $self->SUPER::init_others;

    $self->{LDLOADLIBS} ||= $Config{libs};
    # -Lfoo must come first for Borland, so we put it in LDDLFLAGS
    if ($BORLAND) {
        my $libs = $self->{LDLOADLIBS};
        my $libpath = '';
        while ($libs =~ s/(?:^|\s)(("?)-L.+?\2)(?:\s|$)/ /) {
            $libpath .= ' ' if length $libpath;
            $libpath .= $1;
        }
        $self->{LDLOADLIBS} = $libs;
        $self->{LDDLFLAGS} ||= $Config{lddlflags};
        $self->{LDDLFLAGS} .= " $libpath";
    }

    return;
}



sub init_platform {
    my($self) = shift;

    $self->{MM_Win32_VERSION} = $VERSION;

    return;
}

sub platform_constants {
    my($self) = shift;
    my $make_frag = '';

    foreach my $macro (qw(MM_Win32_VERSION))
    {
        next unless defined $self->{$macro};
        $make_frag .= "$macro = $self->{$macro}\n";
    }

    return $make_frag;
}


sub specify_shell {
    my $self = shift;
    return '' unless $self->is_make_type('gmake');
    "\nSHELL = $ENV{COMSPEC}\n";
}


sub constants {
    my $self = shift;

    my $make_text = $self->SUPER::constants;
    return $make_text unless $self->is_make_type('dmake');

    # dmake won't read any single "line" (even those with escaped newlines)
    # larger than a certain size which can be as small as 8k.  PM_TO_BLIB
    # on large modules like DateTime::TimeZone can create lines over 32k.
    # So we'll crank it up to a <ironic>WHOPPING</ironic> 64k.
    #
    # This has to come here before all the constants and not in
    # platform_constants which is after constants.
    my $size = $self->{MAXLINELENGTH} || 800000;
    my $prefix = qq{
MAXLINELENGTH = $size

};

    return $prefix . $make_text;
}



sub special_targets {
    my($self) = @_;

    my $make_frag = $self->SUPER::special_targets;

    $make_frag .= <<'MAKE_FRAG' if $self->is_make_type('dmake');
.USESHELL :
MAKE_FRAG

    return $make_frag;
}


sub static_lib_pure_cmd {
    my ($self, $from) = @_;
    $from =~ s/(\$\(\w+)(\))/$1:^"+"$2/g if $BORLAND;
    sprintf qq{\t\$(AR) %s\n}, ($BORLAND ? '$@ ' . $from
                          : ($GCC ? '-ru $@ ' . $from
                                  : '-out:$@ ' . $from));
}


sub xs_make_dynamic_lib {
    my ($self, $attribs, $from, $to, $todir, $ldfrom, $exportlist) = @_;
    my @m = sprintf '%s : %s $(MYEXTLIB) %s$(DFSEP).exists %s $(PERL_ARCHIVEDEP) $(INST_DYNAMIC_DEP)'."\n", $to, $from, $todir, $exportlist;
    if ($GCC) {
      # per https://rt.cpan.org/Ticket/Display.html?id=78395 no longer
      # uses dlltool - relies on post 2002 MinGW
      #                             1            2
      push @m, _sprintf562 <<'EOF', $exportlist, $ldfrom;
	$(LD) %1$s -o $@ $(LDDLFLAGS) %2$s $(OTHERLDFLAGS) $(MYEXTLIB) "$(PERL_ARCHIVE)" $(LDLOADLIBS) -Wl,--enable-auto-image-base
EOF
    } elsif ($BORLAND) {
      my $ldargs = $self->is_make_type('dmake')
          ? q{"$(PERL_ARCHIVE:s,/,\,)" $(LDLOADLIBS:s,/,\,) $(MYEXTLIB:s,/,\,),}
          : q{"$(subst /,\,$(PERL_ARCHIVE))" $(subst /,\,$(LDLOADLIBS)) $(subst /,\,$(MYEXTLIB)),};
      my $subbed;
      if ($exportlist eq '$(EXPORT_LIST)') {
          $subbed = $self->is_make_type('dmake')
              ? q{$(EXPORT_LIST:s,/,\,)}
              : q{$(subst /,\,$(EXPORT_LIST))};
      } else {
            # in XSMULTI, exportlist is per-XS, so have to sub in perl not make
          ($subbed = $exportlist) =~ s#/#\\#g;
      }
      push @m, sprintf <<'EOF', $ldfrom, $ldargs . $subbed;
        $(LD) $(LDDLFLAGS) $(OTHERLDFLAGS) %s,$@,,%s,$(RESFILES)
EOF
    } else {	# VC
      push @m, sprintf <<'EOF', $ldfrom, $exportlist;
	$(LD) -out:$@ $(LDDLFLAGS) %s $(OTHERLDFLAGS) $(MYEXTLIB) "$(PERL_ARCHIVE)" $(LDLOADLIBS) -def:%s
EOF
      # Embed the manifest file if it exists
      push(@m, q{	if exist $@.manifest mt -nologo -manifest $@.manifest -outputresource:$@;2
	if exist $@.manifest del $@.manifest});
    }
    push @m, "\n\t\$(CHMOD) \$(PERM_RWX) \$\@\n";

    join '', @m;
}

sub xs_dynamic_lib_macros {
    my ($self, $attribs) = @_;
    my $otherldflags = $attribs->{OTHERLDFLAGS} || ($BORLAND ? 'c0d32.obj': '');
    my $inst_dynamic_dep = $attribs->{INST_DYNAMIC_DEP} || "";
    sprintf <<'EOF', $otherldflags, $inst_dynamic_dep;
OTHERLDFLAGS = %s
INST_DYNAMIC_DEP = %s
EOF
}


sub extra_clean_files {
    my $self = shift;

    return $GCC ? (qw(dll.base dll.exp)) : ('*.pdb');
}


sub init_linker {
    my $self = shift;

    $self->{PERL_ARCHIVE}       = "\$(PERL_INC)\\$Config{libperl}";
    $self->{PERL_ARCHIVEDEP}    = "\$(PERL_INCDEP)\\$Config{libperl}";
    $self->{PERL_ARCHIVE_AFTER} = '';
    $self->{EXPORT_LIST}        = '$(BASEEXT).def';
}



sub perl_script {
    my($self,$file) = @_;
    return $file if -r $file && -f _;
    return "$file.pl"  if -r "$file.pl" && -f _;
    return "$file.plx" if -r "$file.plx" && -f _;
    return "$file.bat" if -r "$file.bat" && -f _;
    return;
}

sub can_dep_space {
    my ($self) = @_;
    return 0 unless $self->can_load_xs;
    require Win32;
    require File::Spec;
    my ($vol, $dir) = File::Spec->splitpath($INC{'ExtUtils/MakeMaker.pm'});
    # can_dep_space via GetShortPathName, if short paths are supported
    my $canary = Win32::GetShortPathName(File::Spec->catpath($vol, $dir, 'MakeMaker.pm'));
    (undef, undef, my $file) = File::Spec->splitpath($canary);
    return (length $file > 11) ? 0 : 1;
}


sub quote_dep {
    my ($self, $arg) = @_;
    if ($arg =~ / / and not $self->is_make_type('gmake')) {
        require Win32;
        $arg = Win32::GetShortPathName($arg);
        die <<EOF if not defined $arg or $arg =~ / /;
Tried to use make dependency with space for non-GNU make:
  '$arg'
Fallback to short pathname failed.
EOF
        return $arg;
    }
    return $self->SUPER::quote_dep($arg);
}



sub xs_obj_opt {
    my ($self, $output_file) = @_;
    ($MSVC ? "/Fo" : "-o ") . $output_file;
}



sub pasthru {
    my($self) = shift;
    my $old = $self->SUPER::pasthru;
    return $old unless $self->is_make_type('nmake');
    $old =~ s/(PASTHRU\s*=\s*)/$1 -nologo /;
    $old;
}



sub arch_check {
    my $self = shift;

    # Win32 is an XS module, minperl won't have it.
    # arch_check() is not critical, so just fake it.
    return 1 unless $self->can_load_xs;
    return $self->SUPER::arch_check( map { $self->_normalize_path_name($_) } @_);
}

sub _normalize_path_name {
    my $self = shift;
    my $file = shift;

    require Win32;
    my $short = Win32::GetShortPathName($file);
    return defined $short ? lc $short : lc $file;
}



sub oneliner {
    my($self, $cmd, $switches) = @_;
    $switches = [] unless defined $switches;

    # Strip leading and trailing newlines
    $cmd =~ s{^\n+}{};
    $cmd =~ s{\n+$}{};

    $cmd = $self->quote_literal($cmd);
    $cmd = $self->escape_newlines($cmd);

    $switches = join ' ', @$switches;

    return qq{\$(ABSPERLRUN) $switches -e $cmd --};
}


sub quote_literal {
    my($self, $text, $opts) = @_;
    $opts->{allow_variables} = 1 unless defined $opts->{allow_variables};

    # See: http://www.autohotkey.net/~deleyd/parameters/parameters.htm#CPP

    # Apply the Microsoft C/C++ parsing rules
    $text =~ s{\\\\"}{\\\\\\\\\\"}g;  # \\" -> \\\\\"
    $text =~ s{(?<!\\)\\"}{\\\\\\"}g; # \"  -> \\\"
    $text =~ s{(?<!\\)"}{\\"}g;       # "   -> \"
    $text = qq{"$text"} if $text =~ /[ \t#]/; # hash because gmake 4.2.1

    # Apply the Command Prompt parsing rules (cmd.exe)
    my @text = split /("[^"]*")/, $text;
    # We should also escape parentheses, but it breaks one-liners containing
    # $(MACRO)s in makefiles.
    s{([<>|&^@!])}{^$1}g foreach grep { !/^"[^"]*"$/ } @text;
    $text = join('', @text);

    # dmake expands {{ to { and }} to }.
    if( $self->is_make_type('dmake') ) {
        $text =~ s/{/{{/g;
        $text =~ s/}/}}/g;
    }

    $text = $opts->{allow_variables}
      ? $self->escape_dollarsigns($text) : $self->escape_all_dollarsigns($text);

    return $text;
}


sub escape_newlines {
    my($self, $text) = @_;

    # Escape newlines
    $text =~ s{\n}{\\\n}g;

    return $text;
}



sub cd {
    my($self, $dir, @cmds) = @_;

    return $self->SUPER::cd($dir, @cmds) unless $self->is_make_type('nmake');

    my $cmd = join "\n\t", map "$_", @cmds;

    my $updirs = $self->catdir(map { $self->updir } $self->splitdir($dir));

    # No leading tab and no trailing newline makes for easier embedding.
    my $make_frag = sprintf <<'MAKE_FRAG', $dir, $cmd, $updirs;
cd %s
	%s
	cd %s
MAKE_FRAG

    chomp $make_frag;

    return $make_frag;
}



sub max_exec_len {
    my $self = shift;

    return $self->{_MAX_EXEC_LEN} ||= 2 * 1024;
}



sub os_flavor {
    return('Win32');
}


sub dbgoutflag {
    $MSVC ? '-Fd$(*).pdb' : '';
}


sub cflags {
    my($self,$libperl)=@_;
    return $self->{CFLAGS} if $self->{CFLAGS};
    return '' unless $self->needs_linking();

    my $base = $self->SUPER::cflags($libperl);
    foreach (split /\n/, $base) {
        /^(\S*)\s*=\s*(\S*)$/ and $self->{$1} = $2;
    };
    $self->{CCFLAGS} .= " -DPERLDLL" if ($self->{LINKTYPE} eq 'static');

    return $self->{CFLAGS} = qq{
CCFLAGS = $self->{CCFLAGS}
OPTIMIZE = $self->{OPTIMIZE}
PERLTYPE = $self->{PERLTYPE}
};

}


sub make_type {
    my ($self) = @_;
    my $make = $self->make;
    $make = +( File::Spec->splitpath( $make ) )[-1];
    $make =~ s!\.exe$!!i;
    if ( $make =~ m![^A-Z0-9]!i ) {
      ($make) = grep { m!make!i } split m![^A-Z0-9]!i, $make;
    }
    return "$make-style";
}

1;
__END__

