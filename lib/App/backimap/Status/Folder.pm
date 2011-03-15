package App::backimap::Status::Folder;
# ABSTRACT: backimap folder status

use Moose;
use MooseX::Storage;
with Storage;

has count => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

has unseen => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

1;
