#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

use TOML::XS;

my $toml = <<END;
# This is a TOML document

"Löwe" = "Löwe"
boolean = false
integer = 123
double = 34.5
timestamp = 1979-05-27T07:32:00-08:00
somearray = []

[checkextra]
"Löwe" = "Löwe"
alltypes = [ { foo = "bar" }, [123], "yes" ]
boolean = false
integer = 123
double = 34.5
timestamp = 1979-05-27T07:32:00-08:00
END

my $docobj = TOML::XS::from_toml($toml);

cmp_deeply(
    $docobj->get('checkextra', 'alltypes', 0),
    { foo => 'bar' },
    'get 0',
);

cmp_deeply(
    $docobj->get('checkextra', 'alltypes', 1),
    [123],
    'get 1',
);

cmp_deeply(
    $docobj->get('checkextra', 'alltypes', 1, 0),
    123,
    'get 1.0',
);

eval { $docobj->get('checkextra', 'alltypes', -1) };
my $err = $@;
like($err, qr<-1>, "negative index to array shows up in error");

done_testing;
