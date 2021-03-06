package TOML::XS;

use strict;
use warnings;

our ($VERSION);

use Types::Serialiser ();

use XSLoader ();

BEGIN {
    $VERSION = '0.05';
    XSLoader::load( __PACKAGE__, $VERSION );
}

=encoding utf8

=head1 NAME

TOML::XS - Turbo-charged L<TOML|https://toml.io> parsing!

=begin html

<a href='https://coveralls.io/github/FGasper/p5-TOML-XS?branch=master'><img src='https://coveralls.io/repos/github/FGasper/p5-TOML-XS/badge.svg?branch=master' alt='Coverage Status' /></a>

=end html

=head1 SYNOPSIS

    # NB: Don’t read_text(), or stuff may break.
    my $toml = File::Slurper::read_binary('/path/to/toml/file');

    my $struct = TOML::XS::from_toml($toml)->to_struct();

=head1 DESCRIPTION

This module facilitates parsing of TOML documents in Perl via XS,
which can yield dramatic performance gains relative to pure-Perl TOML
libraries.

It is currently implemented as a wrapper around the
L<tomlc99|https://github.com/cktan/tomlc99> C library.

=head1 FUNCTIONS

=head2 $doc = TOML::XS::from_toml($byte_string)

Converts a byte string (i.e., raw, undecoded bytes) that contains a
serialized TOML document to a L<TOML::XS::Document> instance.

Throws a suitable exception if the TOML document is unparseable. This
doesn’t necessarily mean that I<any> malformed TOML content triggers such
an error; for example, if an individual data item is malformed but the
document is otherwise valid, this may return successful.

=head1 MAPPING TOML TO PERL

Most TOML data items map naturally to Perl. The following details
are relevant:

=over

=item * Strings are character-decoded.

=item * Booleans are represented as L<TOML::XS::true> and L<TOML::XS::false>,
which are namespace aliases for the relevant constants from
L<Types::Serialiser>.

=item * Timestamps are represented as L<TOML::XS::Timestamp> instances.

=back

=head1 NOTE ON CHARACTER DECODING

This library mimics the default behaviour of popular JSON modules:
the TOML input to the parser is expected to be a byte string, while the
strings that the parser outputs are character strings.

=head1 PERFORMANCE

On my system the included (I<very> simple!) benchmark outputs:

    Including TOML::Tiny …

    small …
                Rate toml_tiny   toml_xs
    toml_tiny  1009/s        --      -95%
    toml_xs   21721/s     2053%        --

    large …
                (warning: too few iterations for a reliable count)
              s/iter toml_tiny   toml_xs
    toml_tiny   1.65        --      -93%
    toml_xs    0.110     1400%        --

=cut

#----------------------------------------------------------------------

*true = *Types::Serialiser::true;
*false = *Types::Serialiser::false;

sub _croak_malformed_toml {
    my $path_ar = shift;

    return _croak_with_pointer('Malformed TOML value found!', $path_ar);
}

sub _croak_pointer_beyond_datum {
    my $path_ar = shift;

    return _croak_with_pointer('Can’t descend into non-container!', $path_ar);
}

sub _croak_with_pointer {
    my ($msg, $path_ar) = @_;

    die sprintf( "%s (JSON pointer: %s)", $msg, _BUILD_JSON_POINTER($path_ar) );
}

sub _BUILD_JSON_POINTER {
    my $pieces_ar = shift;

    my @pieces =  @$pieces_ar;

    s<~><~0>g for @pieces;
    s</><~1>g for @pieces;

    return join('/', q<>, @pieces);
}

#----------------------------------------------------------------------

=head1 COPYRIGHT & LICENSE

Copyright 2021 Gasper Software Consulting. All rights reserved.

This library is licensed under the same license as Perl itself.

L<tomlc99|https://github.com/cktan/tomlc99> is licensed under the
L<MIT License|https://mit-license.org/>.

=cut

1;
