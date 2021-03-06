package PDT::TS::Whois::Redaction;
use strict;
use warnings;
use utf8;

use Carp;
use File::Slurp;
use Readonly;
use Text::CSV;

=head1 EXPORTS

=over 4

=item L<add_redaction_types>

=item L<parse_redaction_db>

=item L<scrub>

=back

=cut

require Exporter;
our @ISA       = 'Exporter';
our @EXPORT_OK = qw( &scrub &add_redaction_types &parse_redaction_db );

Readonly my $DEFAULT_PRIVACY_REDACT_STRING => 'REDACTED FOR PRIVACY';
Readonly my $DEFAULT_CONTACT_REDACT_STRING => 'Please query the RDDS service of the Registrar of Record identified in this output for information on how to contact the Registrant, Admin, or Tech contact of the queried domain name.';

=head1 SUBROUTINES

=head2 scrub

Scrub whitespace within a string.

    my $value = scrub( "scrub   multiple   spaces \t and\ttabs" );
    ( $value eq 'scrub multiple spaces and tabs' ) or die;

Any sequence of consecutive horizontal whitespace characters are replaced with a
single SPACE (U+0020) character.

Differences in amounts of whitespace is considered within the bounds of what's
substantially similar w.r.t. redaction strings.

=cut

sub scrub {
    my $value = shift;

    if ( defined $value ) {
        $value =~ s/\h+/ /g;
    }

    return $value;
}

=head2 parse_redaction_db

Parse a redaction database file.

Takes a single argument: an arrayref of lines from a database file.

Returns a hash with the two keys "privacy" and "contact".
Each one maps to a set of redaction strings (implemented as hashes mapping
redaction strings to the value 1).

Dies if the input is invalid or if there is a problem with Text::CSV.

=cut

sub parse_redaction_db {
    my @db_lines = @{ ( shift ) };

    my $csv = Text::CSV->new( { binary => 1 } )
      or croak "Can't use CSV: " . Text::CSV->error_diag();
    $csv->allow_whitespace( 1 );

    my %redaction_strings = (
        privacy => {},
        contact => {},
    );

    my $line_count = 0;
    for my $line ( @db_lines ) {
        $line_count++;
        chomp $line;

        # Ignore empty lines and comment lines
        if ( $line =~ /^(?:#|$)/ ) {
            next;
        }

        $csv->parse( $line ) or die Text::CSV->error_diag();
        my ( $type, $string, @extra_fields ) = $csv->fields();

        if ( !defined $string ) {
            die "Invalid record on line $line_count\n";
        }

        my $scrubbed_string = scrub( $string );
        if ( $scrubbed_string ne $string ) {
            die "Illegal whitepace in redaction string on line $line_count\n";
        }

        if ( lc $type eq 'privacy' ) {
            $redaction_strings{privacy}{$scrubbed_string} = 1;
        }
        elsif ( lc $type eq 'contact' ) {
            $redaction_strings{contact}{$scrubbed_string} = 1;
        }
        else {
            die "Unknown string type on line $line_count";
        }

        if ( @extra_fields ) {
            die "Extra fields on line $line_count";
        }
    }

    return %redaction_strings;
}

=head2 add_redaction_types

Add data types for redacted fields to a PDT::TS::Whois::Types object.

Takes two arguments.
The first one is the PDT::TS::Whois::Types to be updated.
The second one represents two sets of additional allowed redaction strings;
its a hashref in the format returned by L<parse_redaction_db>.

The two default redaction strings are case-insensitive, but the provided additional
strings are case-sensitive.

The following data types are added:

=over 4

=item redact string

=item email redact string

=item roid or redacted

=item token or redacted

=item postal code or redacted

=item country code or redacted

=item phone number or redacted

=item email web or redacted

=back

=cut

sub add_redaction_types {
    my $types = shift;
    my %redaction_strings = %{ ( shift ) };
    $types->add_type(
        'redact string' => sub {
            my $value = shift;

            $value = scrub( $value );

            if ( defined $value
                && ( lc $value eq lc $DEFAULT_PRIVACY_REDACT_STRING || $redaction_strings{privacy}{$value} ) )
            {
                return ();
            }
            else {
                return ( 'must be a valid Redact String' );
            }
        }
    );
    $types->add_type(
        'email redact string' => sub {
            my $value = shift;

            $value = scrub( $value );

            if ( defined $value
                && ( lc $value eq lc $DEFAULT_CONTACT_REDACT_STRING || $redaction_strings{contact}{$value} ) )
            {
                return ();
            }
            else {
                return ( 'must be a valid Email redact string' );
            }
        }
    );
    $types->add_type(
        'roid or redacted' => sub {
            my $value         = shift;
            my $base_type_err = $types->validate_type( 'roid', $value );
            my $redact_err    = $types->validate_type( 'redact string', $value );
            if ( $base_type_err && $redact_err ) {
                return ( 'must be either a ROID or a Redact String' );
            }
            else {
                return ();
            }
        }
    );
    $types->add_type(
        'token or redacted' => sub {
            my $value         = shift;
            my $base_type_err = $types->validate_type( 'token', $value );
            my $redact_err    = $types->validate_type( 'redact string', $value );
            if ( $base_type_err && $redact_err ) {
                return ( 'must be either a Token or a Redact String' );
            }
            else {
                return ();
            }
        }
    );
    $types->add_type(
        'postal code or redacted' => sub {
            my $value           = shift;
            my $postal_code_err = $types->validate_type( 'postal code', $value );
            my $base_type_err   = $types->validate_type( 'redact string', $value );
            if ( $postal_code_err && $base_type_err ) {
                return ( 'must be either a Postal code or a Redact String' );
            }
            else {
                return ();
            }
        }
    );
    $types->add_type(
        'country code or redacted' => sub {
            my $value         = shift;
            my $base_type_err = $types->validate_type( 'country code', $value );
            my $redact_err    = $types->validate_type( 'redact string', $value );
            if ( $base_type_err && $redact_err ) {
                return ( 'must be either a Country code or a Redact String' );
            }
            else {
                return ();
            }
        }
    );
    $types->add_type(
        'phone number or redacted' => sub {
            my $value         = shift;
            my $base_type_err = $types->validate_type( 'phone number', $value );
            my $redact_err    = $types->validate_type( 'redact string', $value );
            if ( $base_type_err && $redact_err ) {
                return ( 'must be either a Phone number or a Redact String' );
            }
            else {
                return ();
            }
        }
    );
    $types->add_type(
        'email web or redacted' => sub {
            my $value          = shift;
            my $base_type1_err = $types->validate_type( 'email address', $value );
            my $base_type2_err = $types->validate_type( 'http url', $value );
            my $redact_err     = $types->validate_type( 'email redact string', $value );

            if ( $base_type1_err && $base_type2_err && $redact_err ) {
                return ( 'must be either an Email address, an HTTP URL or an Email redact string' );
            }
            else {
                return ();
            }
        }
    );

    return;
}

1;
