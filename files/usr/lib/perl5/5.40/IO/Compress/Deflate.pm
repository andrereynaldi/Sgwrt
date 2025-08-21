package IO::Compress::Deflate ;

require 5.006 ;

use strict ;
use warnings;
use bytes;

require Exporter ;

use IO::Compress::RawDeflate 2.212 ();
use IO::Compress::Adapter::Deflate 2.212 ;

use IO::Compress::Zlib::Constants 2.212 ;
use IO::Compress::Base::Common  2.212 qw();


our ($VERSION, @ISA, @EXPORT_OK, %EXPORT_TAGS, %DEFLATE_CONSTANTS, $DeflateError);

$VERSION = '2.212';
$DeflateError = '';

@ISA    = qw(IO::Compress::RawDeflate Exporter);
@EXPORT_OK = qw( $DeflateError deflate ) ;
%EXPORT_TAGS = %IO::Compress::RawDeflate::DEFLATE_CONSTANTS ;

push @{ $EXPORT_TAGS{all} }, @EXPORT_OK ;
Exporter::export_ok_tags('all');


sub new
{
    my $class = shift ;

    my $obj = IO::Compress::Base::Common::createSelfTiedObject($class, \$DeflateError);
    return $obj->_create(undef, @_);
}

sub deflate
{
    my $obj = IO::Compress::Base::Common::createSelfTiedObject(undef, \$DeflateError);
    return $obj->_def(@_);
}

sub mkComp
{
    my $self = shift ;
    my $got = shift ;

    my ($obj, $errstr, $errno) = IO::Compress::Adapter::Deflate::mkCompObject1(
                                                 $got->getValue('crc32'),
                                                 $got->getValue('adler32'),
                                                 $got->getValue('level'),
                                                 $got->getValue('strategy')
                                                 );

   return $self->saveErrorString(undef, $errstr, $errno)
       if ! defined $obj;

   return $obj;
}


sub mkHeader
{
    my $self = shift ;
    return '';
}

sub mkTrailer
{
    my $self = shift ;
    return '';
}

sub mkFinalTrailer
{
    return '';
}

sub getExtraParams
{
    my $self = shift ;
    return $self->getZlibParams(),
}

sub getInverseClass
{
    no warnings 'once';
    return ('IO::Uncompress::Inflate',
                \$IO::Uncompress::Inflate::InflateError);
}

sub getFileInfo
{
    my $self = shift ;
    my $params = shift;
    my $file = shift ;

}



1;

__END__

