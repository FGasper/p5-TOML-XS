package TOML::XS;

use strict;
use warnings;

our ($VERSION);

use Types::Serialiser ();

use XSLoader ();

BEGIN {
    $VERSION = '0.01_01';
    XSLoader::load();
}

=encoding utf8

=head1 NAME

TOML::XS - Parse L<TOML|https://toml.io> with XS

=head1 SYNOPSIS

    # Yes, read_binary(). Don’t read_text().
    my $toml = File::Slurper::read_binary('/path/to/toml/file');

    my $struct = TOML::XS::from_toml($toml)->to_struct();

=head1 DESCRIPTION

This module facilitates parsing of TOML documents in Perl via XS,
which should offer much greater speed than pure-Perl TOML parsers.

It is currently implemented as a wrapper around the
L<tomlc99|https://github.com/cktan/tomlc99> C library.

=head1 FUNCTIONS

=head2 $doc = TOML::XS::from_toml($byte_string)

Converts a byte string (i.e., raw, undecoded bytes) that contains a
serialized TOML document to a L<TOML::XS::Document> instance.

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

=cut

#----------------------------------------------------------------------

*true = *Types::Serialiser::true;
*false = *Types::Serialiser::false;

#----------------------------------------------------------------------

=head1 COPYRIGHT & LICENSE

Copyright 2021 Gasper Software Consulting. All rights reserved.

This library is licensed under the same license as Perl itself.

L<tomlc99|https://github.com/cktan/tomlc99> is licensed under the
L<MIT License|https://mit-license.org/>.

=cut

1;
