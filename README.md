# NAME

TOML::XS - Parse [TOML](https://toml.io) with XS

# SYNOPSIS

    # NB: Don’t read_text(), or stuff may break.
    my $toml = File::Slurper::read_binary('/path/to/toml/file');

    my $struct = TOML::XS::from_toml($toml)->to_struct();

# DESCRIPTION

This module facilitates parsing of TOML documents in Perl via XS,
which should offer much greater speed than pure-Perl TOML parsers.

It is currently implemented as a wrapper around the
[tomlc99](https://github.com/cktan/tomlc99) C library.

# FUNCTIONS

## $doc = TOML::XS::from\_toml($byte\_string)

Converts a byte string (i.e., raw, undecoded bytes) that contains a
serialized TOML document to a [TOML::XS::Document](https://metacpan.org/pod/TOML::XS::Document) instance.

# MAPPING TOML TO PERL

Most TOML data items map naturally to Perl. The following details
are relevant:

- Strings are character-decoded.
- Booleans are represented as [TOML::XS::true](https://metacpan.org/pod/TOML::XS::true) and [TOML::XS::false](https://metacpan.org/pod/TOML::XS::false),
which are namespace aliases for the relevant constants from
[Types::Serialiser](https://metacpan.org/pod/Types::Serialiser).
- Timestamps are represented as [TOML::XS::Timestamp](https://metacpan.org/pod/TOML::XS::Timestamp) instances.

# NOTE ON CHARACTER DECODING

This library mimics the default configuration of popular JSON modules:
the TOML input to the parser is expected to be a byte string, while the
strings that the parser outputs are character strings.

# COPYRIGHT & LICENSE

Copyright 2021 Gasper Software Consulting. All rights reserved.

This library is licensed under the same license as Perl itself.

[tomlc99](https://github.com/cktan/tomlc99) is licensed under the
[MIT License](https://mit-license.org/).
