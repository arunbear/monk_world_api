package MonkWorld::API::Request;

=head1 NAME

MonkWorld::API::Request - A helper class for building API requests

=head1 DESCRIPTION

This class helps build API requests from HAL links, making it easier to work with
hypermedia APIs.

=cut

use v5.40;
use Moo;
use namespace::autoclean;
use Storable qw(dclone);
use Types::Standard qw(Bool Enum HashRef Maybe StrMatch Str);

my $HttpMethod = Enum [qw(HEAD GET POST PUT DELETE PATCH)];
my $NoSpaces = StrMatch[qr/^ [[:^space:]]+ $/x];

my $Word = qr{
    [[:alnum:]]+     # one or more alphanumerics
    (?:-[a-z]+)*     # optional hyphenated parts
}x;
my $Path = qr{
    ^/               # leading slash
    (?:              # optional segments
        $Word
        (?:/$Word)*  # additional segments
    )?
    /?               # optional slash
    $                # end of string
}x;
my $RelativeUri = StrMatch[qr{$Path}];

# For constructor
has _with_auth_token => (
    is => 'ro',
    init_arg => 'with_auth_token',
    isa => Bool,
    default => true,
);
has _link_meta => (
    is => 'ro',
    init_arg => 'link_meta',
    required => true,
    isa => HashRef,
);
has _server => (
    is => 'ro',
    init_arg => 'server',
    reader => 'server',
    isa => Maybe[Str],
);

# accessors
has _method => (
    is => 'rw', init_arg => undef,
    reader => 'method',
    isa => $HttpMethod,
);
has _href => (
    is => 'rw', init_arg => undef,
    isa => $RelativeUri,
);

sub href ($self) {
    my $server = $self->server // '';
    $server =~ s|/$||;
    return $server . $self->_href;
}

has _headers => (
    is => 'rw', init_arg => undef,
    reader => 'headers',
    isa => Maybe[HashRef],
);
has _json => (
    is => 'rw', init_arg => undef,
    reader => 'json',
    isa => Maybe[HashRef],
);
has _form => (
    is => 'rw', init_arg => undef,
    reader => 'form',
    isa => Maybe[HashRef],
);

sub BUILD ($self, $args) {
    my $link = dclone($self->_link_meta); # avoid modifying the original
    $self->_method($link->{method});
    $self->_href($link->{href});
    $self->_headers($link->{headers} // {});
    $self->_json($link->{json} // {});
    $self->_form($link->{form} // {});
    $self->_add_bearer_token($ENV{MONKWORLD_AUTH_TOKEN}) if $self->_with_auth_token;
}

sub _add_bearer_token ($self, $token) {
    $NoSpaces->assert_valid($token);
    for my ($val) (values $self->headers->%*) {
        if ($val eq 'Bearer %s') {
            $val = sprintf($val, $token);
            last;
        }
    }
    return $self;
}

sub replace_json_val ($self, $old_val, $new_val) {
    for my ($val) (values $self->json->%*) {
        if ($val eq $old_val) {
            $val = $new_val;
            last;
        }
    }
    return $self;
}

sub update_json_kv ($self, $key, $value) {
    $self->json->{$key} = $value;
    return $self;
}

sub update_json_entries ($self, %updates) {
    while (my ($key, $value) = each %updates) {
        $self->json->{$key} = $value;
    }
    return $self;
}

sub ignore_json_kv ($self, $key) {
    delete $self->json->{$key};
    return $self;
}

sub update_form_entries ($self, %updates) {
    while (my ($key, $value) = each %updates) {
        $self->form->{$key} = $value;
    }
    return $self;
}

sub add_uri_segment ($self, $segment) {
    my $separator = $self->href =~ m{/$} ? '' : '/';
    $self->_href($self->href . $separator . $segment);
    return $self;
}

sub tx_args ($self) {
    my $has_form = $self->form && scalar keys $self->form->%*;
    my $payload_key = $has_form ? 'form' : 'json';
    my $payload     = $has_form ? $self->form : $self->json;
    return ($self->method => $self->href => $self->headers => $payload_key => $payload);
}