package Time::tm 1.01;
use v5.38;

use Class::Struct qw(struct);
struct('Time::tm' => [
     map { $_ => '$' } qw{ sec min hour mday mon year wday yday isdst }
]);

__END__

