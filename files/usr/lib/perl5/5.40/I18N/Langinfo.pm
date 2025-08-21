package I18N::Langinfo;

use 5.006;
use strict;
use warnings;
use Carp;

use Exporter 'import';
require XSLoader;

our @EXPORT = qw(langinfo);

our @EXPORT_OK = qw(
                    ABDAY_1
                    ABDAY_2
                    ABDAY_3
                    ABDAY_4
                    ABDAY_5
                    ABDAY_6
                    ABDAY_7
                    ABMON_1
                    ABMON_2
                    ABMON_3
                    ABMON_4
                    ABMON_5
                    ABMON_6
                    ABMON_7
                    ABMON_8
                    ABMON_9
                    ABMON_10
                    ABMON_11
                    ABMON_12
                    ALT_DIGITS
                    AM_STR
                    CODESET
                    CRNCYSTR
                    DAY_1
                    DAY_2
                    DAY_3
                    DAY_4
                    DAY_5
                    DAY_6
                    DAY_7
                    D_FMT
                    D_T_FMT
                    ERA
                    ERA_D_FMT
                    ERA_D_T_FMT
                    ERA_T_FMT
                    MON_1
                    MON_2
                    MON_3
                    MON_4
                    MON_5
                    MON_6
                    MON_7
                    MON_8
                    MON_9
                    MON_10
                    MON_11
                    MON_12
                    NOEXPR
                    NOSTR
                    PM_STR
                    RADIXCHAR
                    THOUSEP
                    T_FMT
                    T_FMT_AMPM
                    YESEXPR
                    YESSTR
                    _NL_ADDRESS_POSTAL_FMT
                    _NL_ADDRESS_COUNTRY_NAME
                    _NL_ADDRESS_COUNTRY_POST
                    _NL_ADDRESS_COUNTRY_AB2
                    _NL_ADDRESS_COUNTRY_AB3
                    _NL_ADDRESS_COUNTRY_CAR
                    _NL_ADDRESS_COUNTRY_NUM
                    _NL_ADDRESS_COUNTRY_ISBN
                    _NL_ADDRESS_LANG_NAME
                    _NL_ADDRESS_LANG_AB
                    _NL_ADDRESS_LANG_TERM
                    _NL_ADDRESS_LANG_LIB
                    _NL_IDENTIFICATION_TITLE
                    _NL_IDENTIFICATION_SOURCE
                    _NL_IDENTIFICATION_ADDRESS
                    _NL_IDENTIFICATION_CONTACT
                    _NL_IDENTIFICATION_EMAIL
                    _NL_IDENTIFICATION_TEL
                    _NL_IDENTIFICATION_FAX
                    _NL_IDENTIFICATION_LANGUAGE
                    _NL_IDENTIFICATION_TERRITORY
                    _NL_IDENTIFICATION_AUDIENCE
                    _NL_IDENTIFICATION_APPLICATION
                    _NL_IDENTIFICATION_ABBREVIATION
                    _NL_IDENTIFICATION_REVISION
                    _NL_IDENTIFICATION_DATE
                    _NL_IDENTIFICATION_CATEGORY
                    _NL_MEASUREMENT_MEASUREMENT
                    _NL_NAME_NAME_FMT
                    _NL_NAME_NAME_GEN
                    _NL_NAME_NAME_MR
                    _NL_NAME_NAME_MRS
                    _NL_NAME_NAME_MISS
                    _NL_NAME_NAME_MS
                    _NL_PAPER_HEIGHT
                    _NL_PAPER_WIDTH
                    _NL_TELEPHONE_TEL_INT_FMT
                    _NL_TELEPHONE_TEL_DOM_FMT
                    _NL_TELEPHONE_INT_SELECT
                    _NL_TELEPHONE_INT_PREFIX
                   );

our $VERSION = '0.24';

XSLoader::load();

1;
__END__

