package ExtUtils::Manifest; # git description: 1.74-10-g1bddbb0

require Exporter;
use Config;
use File::Basename;
use File::Copy 'copy';
use File::Find;
use File::Spec 0.8;
use Carp;
use strict;
use warnings;

our $VERSION = '1.75';
our @ISA = ('Exporter');
our @EXPORT_OK = qw(mkmanifest
                manicheck  filecheck  fullcheck  skipcheck
                manifind   maniread   manicopy   maniadd
                maniskip
               );

our $Is_VMS   = $^O eq 'VMS';
our $Is_VMS_mode = 0;
our $Is_VMS_lc = 0;
our $Is_VMS_nodot = 0;  # No dots in dir names or double dots in files

if ($Is_VMS) {
    require VMS::Filespec if $Is_VMS;
    my $vms_unix_rpt;
    my $vms_efs;
    my $vms_case;

    $Is_VMS_mode = 1;
    $Is_VMS_lc = 1;
    $Is_VMS_nodot = 1;
    if (eval { local $SIG{__DIE__}; require VMS::Feature; }) {
        $vms_unix_rpt = VMS::Feature::current("filename_unix_report");
        $vms_efs = VMS::Feature::current("efs_charset");
        $vms_case = VMS::Feature::current("efs_case_preserve");
    } else {
        my $unix_rpt = $ENV{'DECC$FILENAME_UNIX_REPORT'} || '';
        my $efs_charset = $ENV{'DECC$EFS_CHARSET'} || '';
        my $efs_case = $ENV{'DECC$EFS_CASE_PRESERVE'} || '';
        $vms_unix_rpt = $unix_rpt =~ /^[ET1]/i;
        $vms_efs = $efs_charset =~ /^[ET1]/i;
        $vms_case = $efs_case =~ /^[ET1]/i;
    }
    $Is_VMS_lc = 0 if ($vms_case);
    $Is_VMS_mode = 0 if ($vms_unix_rpt);
    $Is_VMS_nodot = 0 if ($vms_efs);
}

our $Debug   = $ENV{PERL_MM_MANIFEST_DEBUG} || 0;
our $Verbose = defined $ENV{PERL_MM_MANIFEST_VERBOSE} ?
                   $ENV{PERL_MM_MANIFEST_VERBOSE} : 1;
our $Quiet = 0;
our $MANIFEST = 'MANIFEST';

our $DEFAULT_MSKIP = File::Spec->rel2abs(File::Spec->catfile( dirname(__FILE__), "$MANIFEST.SKIP" ));



sub _sort {
    return sort { lc $a cmp lc $b } @_;
}

sub mkmanifest {
    my $manimiss = 0;
    my $read = (-r 'MANIFEST' && maniread()) or $manimiss++;
    $read = {} if $manimiss;
    my $bakbase = $MANIFEST;
    $bakbase =~ s/\./_/g if $Is_VMS_nodot; # avoid double dots
    rename $MANIFEST, "$bakbase.bak" unless $manimiss;
    open my $fh, '>', $MANIFEST or die "Could not open $MANIFEST: $!";
    binmode $fh, ':raw';
    my $skip = maniskip();
    my $found = manifind();
    my($key,$val,$file,%all);
    %all = (%$found, %$read);
    $all{$MANIFEST} = ($Is_VMS_mode ? "$MANIFEST\t\t" : '') .
                     'This list of files'
        if $manimiss; # add new MANIFEST to known file list
    foreach $file (_sort keys %all) {
        if ($skip->($file)) {
            # Policy: only remove files if they're listed in MANIFEST.SKIP.
            # Don't remove files just because they don't exist.
            warn "Removed from $MANIFEST: $file\n" if $Verbose and exists $read->{$file};
            next;
        }
        if ($Verbose){
            warn "Added to $MANIFEST: $file\n" unless exists $read->{$file};
        }
        my $text = $all{$file};
        my $tabs = (5 - (length($file)+1)/8);
        $tabs = 1 if $tabs < 1;
        $tabs = 0 unless $text;
        if ($file =~ /\s/) {
            $file =~ s/([\\'])/\\$1/g;
            $file = "'$file'";
        }
        print $fh $file, "\t" x $tabs, $text, "\n";
    }
}

sub clean_up_filename {
  my $filename = shift;
  $filename =~ s|^\./||;
  if ( $Is_VMS ) {
      $filename =~ s/\.$//;                           # trim trailing dot
      $filename = VMS::Filespec::unixify($filename);  # unescape spaces, etc.
      if( $Is_VMS_lc ) {
          $filename = lc($filename);
          $filename = uc($filename) if $filename =~ /^MANIFEST(\.SKIP)?$/i;
      }
  }
  return $filename;
}



sub manifind {
    my $p = shift || {};
    my $found = {};

    my $wanted = sub {
        my $name = clean_up_filename($File::Find::name);
        warn "Debug: diskfile $name\n" if $Debug;
        return if -d $_;
        $found->{$name} = "";
    };

    # We have to use "$File::Find::dir/$_" in preprocess, because
    # $File::Find::name is unavailable.
    # Also, it's okay to use / here, because MANIFEST files use Unix-style
    # paths.
    find({wanted => $wanted, follow_fast => 1}, ".");

    return $found;
}



sub manicheck {
    return _check_files();
}



sub filecheck {
    return _check_manifest();
}



sub fullcheck {
    return [_check_files()], [_check_manifest()];
}



sub skipcheck {
    my($p) = @_;
    my $found = manifind();
    my $matches = maniskip();

    my @skipped = ();
    foreach my $file (_sort keys %$found){
        if (&$matches($file)){
            warn "Skipping $file\n" unless $Quiet;
            push @skipped, $file;
            next;
        }
    }

    return @skipped;
}


sub _check_files {
    my $p = shift;
    my $dosnames=(defined(&Dos::UseLFN) && Dos::UseLFN()==0);
    my $read = maniread() || {};
    my $found = manifind($p);

    my(@missfile) = ();
    foreach my $file (_sort keys %$read){
        warn "Debug: manicheck checking from $MANIFEST $file\n" if $Debug;
        if ($dosnames){
            $file = lc $file;
            $file =~ s=(\.(\w|-)+)=substr ($1,0,4)=ge;
            $file =~ s=((\w|-)+)=substr ($1,0,8)=ge;
        }
        unless ( exists $found->{$file} ) {
            warn "No such file: $file\n" unless $Quiet;
            push @missfile, $file;
        }
    }

    return @missfile;
}


sub _check_manifest {
    my($p) = @_;
    my $read = maniread() || {};
    my $found = manifind($p);
    my $skip  = maniskip();

    my @missentry = ();
    foreach my $file (_sort keys %$found){
        next if $skip->($file);
        warn "Debug: manicheck checking from disk $file\n" if $Debug;
        unless ( exists $read->{$file} ) {
            warn "Not in $MANIFEST: $file\n" unless $Quiet;
            push @missentry, $file;
        }
    }

    return @missentry;
}



sub maniread {
    my ($mfile) = @_;
    $mfile ||= $MANIFEST;
    my $read = {};
    my $fh;
    unless (open $fh, '<', $mfile){
        warn "Problem opening $mfile: $!";
        return $read;
    }
    local $_;
    while (<$fh>){
        chomp;
        next if /^\s*#/;

        my($file, $comment);

        # filename may contain spaces if enclosed in ''
        # (in which case, \\ and \' are escapes)
        if (($file, $comment) = /^'((?:\\[\\']|.+)+)'\s*(.*)/) {
            $file =~ s/\\([\\'])/$1/g;
        }
        else {
            ($file, $comment) = /^(\S+)\s*(.*)/;
        }
        next unless $file;

        if ($Is_VMS_mode) {
            require File::Basename;
            my($base,$dir) = File::Basename::fileparse($file);
            # Resolve illegal file specifications in the same way as tar
            if ($Is_VMS_nodot) {
                $dir =~ tr/./_/;
                my(@pieces) = split(/\./,$base);
                if (@pieces > 2)
                    { $base = shift(@pieces) . '.' . join('_',@pieces); }
                my $okfile = "$dir$base";
                warn "Debug: Illegal name $file changed to $okfile\n" if $Debug;
                $file = $okfile;
            }
            if( $Is_VMS_lc ) {
                $file = lc($file);
                $file = uc($file) if $file =~ /^MANIFEST(\.SKIP)?$/i;
            }
        }

        $read->{$file} = $comment;
    }
    $read;
}


sub _process_skipline {
    local $_ = shift;
    chomp;
    s/\r//;
    $_ =~ qr{^\s*(?:(?:'([^\\']*(?:\\.[^\\']*)*)')|([^#\s]\S*))?(?:(?:\s*)|(?:\s+(.*?)\s*))$};
    #my $comment = $3;
    my $filename = $2;
    if ( defined($1) ) {
      $filename = $1;
      $filename =~ s/\\(['\\])/$1/g;
    }
    $filename;
}

sub maniskip {
    my @skip ;
    my $mfile = shift || "$MANIFEST.SKIP";
    _check_mskip_directives($mfile) if -f $mfile;
    local $_;
    my $fh;
    open $fh, '<', $mfile or open $fh, '<', $DEFAULT_MSKIP or return sub {0};
    while (<$fh>){
        if (/^#!include_default\s*$/) {
            if (my @default = _include_mskip_file()) {
                warn "Debug: Including default MANIFEST.SKIP\n" if $Debug;
                push @skip, grep $_, map _process_skipline($_), @default;
            }
            next;
        }
        next unless my $filename = _process_skipline($_);
        push @skip, $filename;
    }
    return sub {0} unless (scalar @skip > 0);

    my $opts = $Is_VMS_mode ? '(?i)' : '';

    # Make sure each entry is isolated in its own parentheses, in case
    # any of them contain alternations
    my $regex = join '|', map "(?:$_)", @skip;

    return sub { $_[0] =~ qr{$opts$regex} };
}

sub _get_homedir {
    $^O eq 'MSWin32' && "$]" < 5.016 ? $ENV{HOME} || $ENV{USERPROFILE} : (glob('~'))[0];
}

sub _check_mskip_directives {
    my $mfile = shift;
    local $_;
    my $fh;
    my @lines = ();
    my $flag = 0;
    unless (open $fh, '<', $mfile) {
        warn "Problem opening $mfile: $!";
        return;
    }
    while (<$fh>) {
        if (/^#!include\s+(.*)\s*$/) {
            my $external_file = $1;
            $external_file =~ s{^~/}{_get_homedir().'/'}e;
            if (my @external = _include_mskip_file($external_file)) {
                push @lines, @external;
                warn "Debug: Including external $external_file\n" if $Debug;
                $flag++;
            }
            next;
        }
        push @lines, $_;
    }
    close $fh;
    return unless $flag;
    my $bakbase = $mfile;
    $bakbase =~ s/\./_/g if $Is_VMS_nodot;  # avoid double dots
    rename $mfile, "$bakbase.bak";
    warn "Debug: Saving original $mfile as $bakbase.bak\n" if $Debug;
    unless (open $fh, '>', $mfile) {
        warn "Problem opening $mfile: $!";
        return;
    }
    binmode $fh, ':raw';
    print $fh $_ for (@lines);
    return;
}

sub _include_mskip_file {
    my $mskip = shift || $DEFAULT_MSKIP;
    unless (-f $mskip) {
        warn qq{Included file "$mskip" not found - skipping};
        return;
    }
    local $_;
    my $fh;
    unless (open $fh, '<', $mskip) {
        warn "Problem opening $mskip: $!";
        return;
    }
    my @lines = ();
    push @lines, "\n#!start included $mskip\n";
    push @lines, $_ while <$fh>;
    push @lines, "#!end included $mskip\n\n";
    return @lines;
}


sub manicopy {
    my($read,$target,$how)=@_;
    croak "manicopy() called without target argument" unless defined $target;
    $how ||= 'cp';
    require File::Path;
    require File::Basename;

    $target = VMS::Filespec::unixify($target) if $Is_VMS_mode;
    File::Path::mkpath([ $target ],! $Quiet,$Is_VMS ? undef : 0755);
    foreach my $file (keys %$read){
        $file = VMS::Filespec::unixify($file) if $Is_VMS_mode;
        if ($file =~ m!/!) { # Ilya, that hurts, I fear, or maybe not?
            my $dir = File::Basename::dirname($file);
            $dir = VMS::Filespec::unixify($dir) if $Is_VMS_mode;
            File::Path::mkpath(["$target/$dir"],! $Quiet,$Is_VMS ? undef : 0755);
        }
        cp_if_diff($file, "$target/$file", $how);
    }
}

sub cp_if_diff {
    my($from, $to, $how)=@_;
    if (! -f $from) {
        carp "$from not found";
        return;
    }
    my($diff) = 0;
    my ($fromfh, $tofh);
    open($fromfh, '<', $from) or die "Can't read $from: $!\n";
    if (open($tofh, '<', $to)) {
        local $_;
        while (<$fromfh>) { $diff++,last if $_ ne <$tofh>; }
        $diff++ unless eof($tofh);
        close $tofh;
    }
    else { $diff++; }
    close $fromfh;
    if ($diff) {
        if (-e $to) {
            unlink($to) or confess "unlink $to: $!";
        }
        STRICT_SWITCH: {
            best($from,$to), last STRICT_SWITCH if $how eq 'best';
            cp($from,$to), last STRICT_SWITCH if $how eq 'cp';
            ln($from,$to), last STRICT_SWITCH if $how eq 'ln';
            croak("ExtUtils::Manifest::cp_if_diff " .
              "called with illegal how argument [$how]. " .
              "Legal values are 'best', 'cp', and 'ln'.");
        }
    }
}

sub cp {
    my ($srcFile, $dstFile) = @_;
    my ($access,$mod) = (stat $srcFile)[8,9];

    copy($srcFile,$dstFile);
    utime $access, $mod + ($Is_VMS ? 1 : 0), $dstFile;
    _manicopy_chmod($srcFile, $dstFile);
}


sub ln {
    my ($srcFile, $dstFile) = @_;
    # Fix-me - VMS can support links.
    return &cp if $Is_VMS or ($^O eq 'MSWin32' and Win32::IsWin95());
    link($srcFile, $dstFile);

    unless( _manicopy_chmod($srcFile, $dstFile) ) {
        unlink $dstFile;
        return;
    }
    1;
}

sub _manicopy_chmod {
    my($srcFile, $dstFile) = @_;

    my $perm = 0444 | (stat $srcFile)[2] & 0700;
    chmod( $perm | ( $perm & 0100 ? 0111 : 0 ), $dstFile );
}

my @Exceptions = qw(MANIFEST META.yml SIGNATURE);
sub best {
    my ($srcFile, $dstFile) = @_;

    my $is_exception = grep $srcFile =~ /$_/, @Exceptions;
    if ($is_exception or !$Config{d_link} or -l $srcFile) {
        cp($srcFile, $dstFile);
    } else {
        ln($srcFile, $dstFile) or cp($srcFile, $dstFile);
    }
}


sub maniadd {
    my($additions) = shift;

    _normalize($additions);
    _fix_manifest($MANIFEST);

    my $manifest = maniread();
    my @needed = grep !exists $manifest->{$_}, keys %$additions;
    return 1 unless @needed;

    open(my $fh, '>>', $MANIFEST) or
      die "maniadd() could not open $MANIFEST: $!";
    binmode $fh, ':raw';

    foreach my $file (_sort @needed) {
        my $comment = $additions->{$file} || '';
        if ($file =~ /\s/) {
            $file =~ s/([\\'])/\\$1/g;
            $file = "'$file'";
        }
        printf $fh "%-40s %s\n", $file, $comment;
    }
    close $fh or die "Error closing $MANIFEST: $!";

    return 1;
}


sub _fix_manifest {
    my $manifest_file = shift;

    open my $fh, '<', $MANIFEST or die "Could not open $MANIFEST: $!";
    local $/;
    my @manifest = split /(\015\012|\012|\015)/, <$fh>, -1;
    close $fh;
    my $must_rewrite = "";
    if ($manifest[-1] eq ""){
        # sane case: last line had a terminal newline
        pop @manifest;
        for (my $i=1; $i<=$#manifest; $i+=2) {
            unless ($manifest[$i] eq "\n") {
                $must_rewrite = "not a newline at pos $i";
                last;
            }
        }
    } else {
        $must_rewrite = "last line without newline";
    }

    if ( $must_rewrite ) {
        1 while unlink $MANIFEST; # avoid multiple versions on VMS
        open $fh, ">", $MANIFEST or die "(must_rewrite=$must_rewrite) Could not open >$MANIFEST: $!";
        binmode $fh, ':raw';
        for (my $i=0; $i<=$#manifest; $i+=2) {
            print $fh "$manifest[$i]\n";
        }
        close $fh or die "could not write $MANIFEST: $!";
    }
}


sub _normalize {
    return;
}


1;
