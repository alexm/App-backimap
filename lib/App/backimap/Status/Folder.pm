package App::backimap::Status::Folder;
# ABSTRACT: backimap folder status

use Moose;
use MooseX::Storage;
with Storage;

=attr count

Total number of messages in a folder.

=cut

has count => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

=attr unseen

Number of unseen messages in a folder.

=cut

has unseen => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

1;
