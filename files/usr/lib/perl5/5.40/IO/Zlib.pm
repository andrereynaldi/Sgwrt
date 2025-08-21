
package IO::Zlib;


require 5.006;

use strict;
use warnings;

use Carp;
use Fcntl qw(SEEK_SET);
use Symbol;
use Tie::Handle;

our $VERSION = "1.15";
our $AUTOLOAD;
our @ISA = qw(Tie::Handle);

my $has_Compress_Zlib;
my $gzip_external;
my $gzip_used;
my $gzip_read_open = "gzip -dc %s |";
my $gzip_write_open = "| gzip > %s";
my $aliased;

BEGIN {
    eval { require Compress::Zlib };
    $has_Compress_Zlib = $@ || $Compress::Zlib::VERSION < 2.000 ? 0 : 1;
}

sub has_Compress_Zlib
{
    $has_Compress_Zlib;
}

sub gzip_external
{
    $gzip_external;
}

sub gzip_used
{
    $gzip_used;
}

sub gzip_read_open
{
    $gzip_read_open;
}

sub gzip_write_open
{
    $gzip_write_open;
}

sub can_gunzip
{
    $has_Compress_Zlib || $gzip_external;
}

sub _import
{
    my $import = shift;

    while (@_)
    {
        if ($_[0] eq ':gzip_external')
        {
            shift;

            if (@_)
            {
                $gzip_external = shift;
            }
            else
            {
                croak "$import: ':gzip_external' requires an argument";
            }
        }
        elsif ($_[0] eq ':gzip_read_open')
        {
            shift;

            if (@_)
            {
                $gzip_read_open = shift;

                croak "$import: ':gzip_read_open' '$gzip_read_open' is illegal"
                    unless $gzip_read_open =~ /^.+%s.+\|\s*$/;
            }
            else
            {
                croak "$import: ':gzip_read_open' requires an argument";
            }
        }
        elsif ($_[0] eq ':gzip_write_open')
        {
            shift;

            if (@_)
            {
                $gzip_write_open = shift;

                croak "$import: ':gzip_write_open' '$gzip_read_open' is illegal"
                    unless $gzip_write_open =~ /^\s*\|.+%s.*$/;
            }
            else
            {
                croak "$import: ':gzip_write_open' requires an argument";
            }
        }
        else
        {
            last;
        }
    }

    return @_;
}

sub _alias
{
    my $import = shift;

    if ($gzip_external || (!$has_Compress_Zlib && !defined($gzip_external)))
    {
        require IO::Handle;

        undef *gzopen;
        *gzopen = \&gzopen_external;

        *IO::Handle::gzread = \&gzread_external;
        *IO::Handle::gzwrite = \&gzwrite_external;
        *IO::Handle::gzreadline = \&gzreadline_external;
        *IO::Handle::gzeof = \&gzeof_external;
        *IO::Handle::gzclose = \&gzclose_external;

        $gzip_used = 1;
    }
    elsif ($has_Compress_Zlib)
    {
        *gzopen = \&Compress::Zlib::gzopen;
        *gzread = \&Compress::Zlib::gzread;
        *gzwrite = \&Compress::Zlib::gzwrite;
        *gzreadline = \&Compress::Zlib::gzreadline;
        *gzeof = \&Compress::Zlib::gzeof;
    }
    else
    {
        croak "$import: no Compress::Zlib and no external gzip";
    }

    $aliased = 1;
}

sub import
{
    my $class = shift;
    my $import = "IO::Zlib::import";

    if (@_)
    {
        if (_import($import, @_))
        {
            croak "$import: '@_' is illegal";
        }
    }

    _alias($import);
}

sub TIEHANDLE
{
    my $class = shift;
    my @args = @_;

    my $self = bless {}, $class;

    return @args ? $self->OPEN(@args) : $self;
}

sub DESTROY
{
}

sub OPEN
{
    my $self = shift;
    my $filename = shift;
    my $mode = shift;

    croak "IO::Zlib::open: needs a filename" unless defined($filename);

    $self->{'file'} = gzopen($filename,$mode);

    return defined($self->{'file'}) ? $self : undef;
}

sub CLOSE
{
    my $self = shift;

    return undef unless defined($self->{'file'});

    my $status = $self->{'file'}->gzclose();

    delete $self->{'file'};

    return ($status == 0) ? 1 : undef;
}

sub READ
{
    my $self = shift;
    my $bufref = \$_[0];
    my $nbytes = $_[1];
    my $offset = $_[2] || 0;

    croak "IO::Zlib::READ: NBYTES must be specified" unless defined($nbytes);

    $$bufref = "" unless defined($$bufref);

    my $bytesread = $self->{'file'}->gzread(substr($$bufref,$offset),$nbytes);

    return undef if $bytesread < 0;

    return $bytesread;
}

sub READLINE
{
    my $self = shift;

    my $line;

    return () if $self->{'file'}->gzreadline($line) <= 0;

    return $line unless wantarray;

    my @lines = $line;

    while ($self->{'file'}->gzreadline($line) > 0)
    {
        push @lines, $line;
    }

    return @lines;
}

sub WRITE
{
    my $self = shift;
    my $buf = shift;
    my $length = shift;
    my $offset = shift;

    croak "IO::Zlib::WRITE: too long LENGTH" unless $offset + $length <= length($buf);

    return $self->{'file'}->gzwrite(substr($buf,$offset,$length));
}

sub EOF
{
    my $self = shift;

    return $self->{'file'}->gzeof();
}

sub FILENO
{
    return undef;
}

sub new
{
    my $class = shift;
    my @args = @_;

    _alias("new", @_) unless $aliased; # Some call new IO::Zlib directly...

    my $self = gensym();

    tie *{$self}, $class, @args;

    return tied(${$self}) ? bless $self, $class : undef;
}

sub getline
{
    my $self = shift;

    return scalar tied(*{$self})->READLINE();
}

sub getlines
{
    my $self = shift;

    croak "IO::Zlib::getlines: must be called in list context"
        unless wantarray;

    return tied(*{$self})->READLINE();
}

sub opened
{
    my $self = shift;

    return defined tied(*{$self})->{'file'};
}

sub AUTOLOAD
{
    my $self = shift;

    $AUTOLOAD =~ s/.*:://;
    $AUTOLOAD =~ tr/a-z/A-Z/;

    return tied(*{$self})->$AUTOLOAD(@_);
}

sub gzopen_external
{
    my $filename = shift;
    my $mode = shift;
    my $fh = IO::Handle->new();

    if ($mode =~ /r/)
    {
        # Because someone will try to read ungzipped files
        # with this we peek and verify the signature.  Yes,
        # this means that we open the file twice (if it is
        # gzipped).
        # Plenty of race conditions exist in this code, but
        # the alternative would be to capture the stderr of
        # gzip and parse it, which would be a portability nightmare.
        if (-e $filename && open($fh, $filename))
        {
            binmode $fh;

            my $sig;
            my $rdb = read($fh, $sig, 2);

            if ($rdb == 2 && $sig eq "\x1F\x8B")
            {
                my $ropen = sprintf($gzip_read_open, $filename);

                if (open($fh, $ropen))
                {
                    binmode $fh;

                    return $fh;
                }
                else
                {
                    return undef;
                }
            }

            seek($fh, 0, SEEK_SET) or
                die "IO::Zlib: open('$filename', 'r'): seek: $!";

            return $fh;
        }
        else
        {
            return undef;
        }
    }
    elsif ($mode =~ /w/)
    {
        my $level = $mode =~ /([1-9])/ ? "-$1" : "";

        # To maximize portability we would need to open
        # two filehandles here, one for "| gzip $level"
        # and another for "> $filename", and then when
        # writing copy bytes from the first to the second.
        # We are using IO::Handle objects for now, however,
        # and they can only contain one stream at a time.
        my $wopen = sprintf($gzip_write_open, $filename);

        if (open($fh, $wopen))
        {
            $fh->autoflush(1);
            binmode $fh;

            return $fh;
        }
        else
        {
            return undef;
        }
    }
    else
    {
        croak "IO::Zlib::gzopen_external: mode '$mode' is illegal";
    }

    return undef;
}

sub gzread_external
{
    my $file = shift;
    my $bufref = \$_[0];
    my $nbytes = $_[1] || 4096;

    # Use read() instead of sysread() because people may
    # mix reads and readlines, and we don't want to mess
    # the stdio buffering.  See also gzreadline_external()
    # and gzwrite_external().
    my $nread = read($file, $$bufref, $nbytes);

    return defined $nread ? $nread : -1;
}

sub gzwrite_external
{
    my $file = shift;
    my $buf = shift;

    # Using syswrite() is okay (cf. gzread_external())
    # since the bytes leave this process and buffering
    # is therefore not an issue.
    my $nwrote = syswrite($file, $buf);

    return defined $nwrote ? $nwrote : -1;
}

sub gzreadline_external
{
    my $file = shift;
    my $bufref = \$_[0];

    # See the comment in gzread_external().
    $$bufref = readline($file);

    return defined $$bufref ? length($$bufref) : -1;
}

sub gzeof_external
{
    my $file = shift;

    return eof($file);
}

sub gzclose_external
{
    my $file = shift;

    close($file);

    # I am not entirely certain why this is needed but it seems
    # the above close() always fails (as if the stream would have
    # been already closed - something to do with using external
    # processes via pipes?)
    return 0;
}

1;
