package App::backimap::Status;
# ABSTRACT: manages backimap status

use Moose;
use MooseX::Storage;
with Storage( 'format' => 'JSON' );
# Storage prereq
use JSON::Any();

use English qw( -no_match_vars );

=attr timestamp

Time of last run started.

=cut

has timestamp => (
    is => 'ro',
    isa => 'Int',
    default => $BASETIME,
    required => 1,
);

=attr server

Server name used in IMAP.

=cut

has server => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=attr user

User name used in IMAP.

=cut

has user => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=attr folder

Collection of folder status.

=cut

has folder => (
    is => 'rw',
    isa => 'HashRef[App::backimap::Status::Folder]',
);

=attr storage

Object to use as the storage backend for status.

=cut

has storage => (
    is => 'ro',
    isa => 'App::backimap::Storage',
);

my $FILENAME = 'backimap.json';

=for Pod::Coverage BUILD

Extra status initialization is not documented.

=cut

sub BUILD {
    my $self = shift;

    return unless $self->storage;

    if ( $self->storage->init ) {
        $self->save();
    }
    else {
        my $json = $self->storage->get($FILENAME);
        my $status = App::backimap::Status->thaw($json);

        die "IMAP credentials do not match saved status\n"
            if $status->user ne $self->user ||
                $status->server ne $self->server;

        $self->folder( $status->folder )
            if $status->folder;
    }
}

=method save

Save status to storage backend.

Returns true if status has actually a storage and saving was successful
or false otherwise.

=cut

sub save {
    my $self = shift;

    return unless $self->storage;

    my $json = $self->freeze();
    $self->storage->put( $FILENAME => $json );

    return 1;
}

1;
