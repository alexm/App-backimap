package App::backimap::Status;
# ABSTRACT: manages backimap status

use Moose;
use MooseX::Storage;
with Storage( 'format' => 'JSON', 'io' => 'File' );

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

1;
