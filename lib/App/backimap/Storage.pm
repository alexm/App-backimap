package App::backimap::Storage;
# ABSTRACT: manages backimap storage

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;
use File::chdir;

=attr dir

Sets pathname to the storage.

=cut

has dir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce => 1,
);

has init => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

subtype 'Git::Wrapper' => as 'Object' => where { $_->isa('Git::Wrapper') };

has _git => (
    is => 'ro',
    isa => 'Git::Wrapper',
    lazy => 1,
    default => sub {
        my $self = shift;

        my $dir = $self->dir;
        my $git = Git::Wrapper->new("$dir");

        if ( $self->init ) {
            die "directory $dir already initialized\n"
                if -d $dir->subdir(".git");

            $dir->mkpath();
            $git->init();
        }

        return $git;
    },
);

=method get( $file )

Retrieves file from storage.

=cut

sub get {
    my $self = shift;
    my ($file) = @_;

    return -f $self->dir->file($file);
}

=method put( $change, $file => $content, ... )

Adds files to storage with a text describing the change.

=cut

sub put {
    my $self = shift;
    my ( $change, %files ) = @_;

    my $dir = $self->dir;
    local $CWD = "$dir";

    for my $filename ( keys %files ) {
        my $filepath = $dir->file($filename);
        $filepath->dir->mkpath()
            unless -d $filepath->dir;

        my $file = $filepath->open('w')
            or die "cannot open $filepath: $!";

        $file->print( $files{$filename} );
        $file->close();

        $self->_git->add($filename);
    }

    if ( keys %files ) {
        $self->_git->commit( { message => $change }, keys %files );
    }
    else {
        $self->_git->add("$dir");
        $self->_git->commit( { message => $change, all => 1 } );
    }
}

1;
