package PDT::TS::Whois::Lexer;
use utf8;
use strict;
use warnings;
use 5.014;

use Carp;

use PDT::TS::Whois::Remark qw( new_remark $ERROR_SEVERITY );

=head1 NAME

PDT::TS::Whois::Lexer - Consumes a string and produces a token/value/errors
triplet for each line.

=cut

=head1 SYNOPSIS

This class breaks its input down into discrete tokens - one for each line.
Unlike what the class name suggests, token values are scrubbed and if anything
mildly illegal is encountered in this process, validation messages are also
returned.

The class provides instance methods to peek at the current line token, get the
current line number and to advance onto the next line.

    use PDT::TS::Whois::Lexer;

    my $lexer = PDT::TS::Whois::Lexer->new("    line 1\r\n This:is:illegal \r\n");
    do {
        my ($token, $value, $errors) = $lexer->peek_line();
        printf("%d: [%s] [%s]", $lexer->line_no(), $token, join(", ", @$errors));

        $lexer->next_line();
    } while ( $token ne 'EOF' );

=head1 CONSTRUCTORS

=head2 new

    my $lexer = PDT::TS::Whois::Lexer->new("    line 1\r\n    line 2\r\n");

Constructs a new Lexer instance.

The C<check_eol> setting is initialized to true.

=cut

sub new {
    my $class     = shift;
    my $text      = shift;

    croak "text: missing argument" unless defined $text;

    my $self = bless {
        _line_no   => undef,
        _lookahead => undef,
        _text      => $text,
        _check_eol => 1,
    }, $class;

    return $self;
}

=head1 INSTANCE METHODS

=head2 check_eol

Get or set the value of the B<check_eol> setting.

This setting controls whether warnings should be generated for unexpected EOL representations.

The expected EOL representation is C<"\r\n">.
C<"\n"> and C<"\r"> on their own are also recognized as EOL representations,
but they are seen as unexpected.

    my $lexer = PDT::TS::Whois::Lexer->new("    line 1\n    line 2\r");
    $lexer->check_eol( 1 );

If no argument is given or if it is C<undef>, the current value is returned.

Otherwise the argument is interpreted using the normal rules for booleans,
the setting is updated to either C<1> for true or C<0> for false,
and the old value is returned.

=cut

sub check_eol {
    my $self  = shift;
    my $value = shift;

    my $old_value = $self->{_check_eol};
    if ( defined $value ) {
        $self->{_check_eol} = $value ? 1 : 0;
    }

    return $old_value;
}

=head2 line_no

    my $line_no = $lexer->line_no();

Get the current line number.

=cut

sub line_no {
    my $self = shift;
    if ( !defined $self->{_lookahead} ) {
        $self->next_line();
    }
    return $self->{_line_no};
}

=head2 peek_line

I<Deprecated>, use L<peek_line2> instead.

L<peek_line> is identical to L<peek_line2>, except it returns strings like
C<"line 1: Boom!"> instead of L<PDT::TS::Whois::Remark> hashrefs.

=cut

sub peek_line {
    my $self = shift;

    my ( $key, $translations, $remark ) = $self->peek_line2();
    if ( defined $remark ) {
        return ( $key, $translations, [ map { sprintf( "line %d: %s", $_->{lineno}, $_->{message} ) } @{$remark} ] );
    }
    else {
        return ( $key, $translations, undef );
    }
}

=head2 peek_line2

    my ($token, $token_value, $remarks) = $lexer->peek_line();

Get the token present at the current line, together with its value and any
validation errors.

=head3 TOKENS

=head4 B<awip line>

Value: undef

=head4 B<empty line>

Value: undef

=head4 B<field>

Value: An arrayref triplet of:
 * a field key string
 * an arrayref of key translation strings
 * a value string or else undef if it is an empty field

=head4 B<last update line>

Value: A time stamp string

=head4 B<multiple name servers line>

Value: undef

=head4 B<non-empty line>

Value: A scrubbed line contents string.

=head4 B<roid line>

Value: An arrayref pair of:
 * a roid string
 * a hostname string

=head4 B<EOF>

Value: undef

=cut

sub peek_line2 {
    my $self = shift;

    if ( !defined $self->{_lookahead} ) {
        $self->next_line();
    }
    return @{ $self->{_lookahead} };
}

=head2 matches

    my $is_comment = $lexer->matches( qr/^#/ );

Test if the current (pre-processed but unparsed) line matches given regular
expression.

=cut

sub matches {
    my $self = shift;
    my $pattern = shift or croak 'Missing argument: $pattern';

    if ( !exists $self->{_lookahead_line} ) {
        $self->next_line();
    }
    return defined $self->{_lookahead_line} && $self->{_lookahead_line} =~ $pattern;
}

=head2 next_line

    $lexer->next_line();

Advance onto the next line.

=cut

sub next_line {
    my $self = shift;

    my $text = $self->{_text};
    my @errors;
    if ( !defined $self->{_line_no} && $text =~ /^\N{U+FEFF}/ ) {
        $text =~ s/^\N{U+FEFF}//;
        push @errors, new_remark( $ERROR_SEVERITY, 1, "found BOM" );
    }

    if ( $self->{_text} eq '' ) {
        if ( !defined $self->{_line_no} ) {
            $self->{_line_no} = 1;
        }
        $self->{_lookahead_line} = undef;
        $self->{_lookahead} = [ 'EOF', undef, \@errors ];
        return;
    }
    $self->{_line_no} ||= 0;
    $self->{_line_no}++;
    $text =~ s/([^\r\n]*)(\r\n?|\n)//;
    my $line = $1;
    my $eol  = $2;
    if ( !defined $eol ) {
        $line = $text;
        $eol  = '';
        $text = '';
    }
    $self->{_text} = $text;

    # Strip CRLF
    if ( $eol ne "\r\n" ) {
        $eol =~ s/\r/CR/m;
        $eol =~ s/\n/LF/m;
        push @errors, new_remark( $ERROR_SEVERITY, $self->{_line_no}, "expected CRLF, got '$eol'" )
          if $self->{_check_eol};
    }

    # Homogenize whitespace
    my $space_count = () = $line =~ / /g;
    $line =~ s/\s/ /g;
    my $whitespace_count = () = $line =~ / /g;
    if ( $whitespace_count > $space_count ) {
        push @errors, new_remark( $ERROR_SEVERITY, $self->{_line_no}, "whitespace other than SPACE (U+0020)" );
    }

    # Strip leading space
    $line =~ s/^( *)//;
    my $lead_space = $1;
    if ( length $lead_space > 9 ) {
        push @errors, new_remark( $ERROR_SEVERITY, $self->{_line_no}, "too much leading space" );
    }

    # Strip trailing space
    $line =~ s/( *)$//;
    my $trail_space = $1;

    # Match token type
    my $token;
    my $token_value;
    if ( $line eq '' ) {
        $token       = 'empty line';
        $token_value = undef;
    }
    elsif ( $line eq 'Query matched more than one name server:' ) {
        $token       = 'multiple name servers line';
        $token_value = undef;
    }
    elsif ( $line =~ /^>>> Last update of (?:WHOIS|Whois) database: (.*) <<<$/ ) {
        my $timestamp = $1;
        $token       = 'last update line';
        $token_value = $timestamp;
    }
    elsif ( $line =~ /^For more information on Whois status codes, please visit (.*)$/ ) {
        my $url = $1;

        # Note: validation is out of place here; move elsewhere if added complexity can be avoided
        if ( $url ne 'https://icann.org/epp' && $url ne 'https://www.icann.org/resources/pages/epp-status-codes-2014-06-16-en' ) {
            push @errors, new_remark( $ERROR_SEVERITY, $self->{_line_no}, 'illegal url' );
        }

        $token       = 'awip line';
        $token_value = undef;
    }
    elsif ( $line =~ /^(?!>>)([^:()]+)(?: \(([^()]+)\))?:(?: (.*))?$/ ) {
        my $key          = $1;
        my @translations = split '/', ( $2 || '' );
        my $value        = $3;

        if ( !defined $value ) {
            $trail_space =~ s/ $//;
        }

        $token = 'field';
        $token_value = [ $key, \@translations, $value ];
    }
    elsif ( $line =~ /^(.*) \((.*)\)$/ ) {
        my $roid     = $1;
        my $hostname = $2;
        $token = 'roid line';
        $token_value = [ $roid, $hostname ];
    }
    else {
        $token       = 'non-empty line';
        $token_value = $line;
    }

    if ( length $trail_space > 0 ) {
        push @errors, new_remark( $ERROR_SEVERITY, $self->{_line_no}, "trailing space not allowed" );
    }

    $self->{_lookahead_line} = $line;
    $self->{_lookahead} = [ $token, $token_value, \@errors ];
    return;
}

1;
