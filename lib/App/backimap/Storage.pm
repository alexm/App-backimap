package App::backimap::Storage;
# ABSTRACT: manages backimap storage

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;
use File::HomeDir;
use Git::Wrapper;

=attr dir

Sets pathname to the storage (defaults to ~/.backimap).

=cut

has dir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce => 1,
    default => sub { File::HomeDir->my_home . ".backimap" },
);

=attr init

Tells that storage must be initialized.

=cut

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

=method find

Returns a list of files that are found in storage.

=cut

sub find {
    my $self = shift;

    my @found = grep { -f $self->dir->file($_) } @_;
    return @found;
}

=method list

Returns a list of files in a directory from storage.

=cut

sub list {
    my $self = shift;
    my ($dir) = @_;

    $dir = $self->dir->subdir($dir);
    my @list = grep !( $_->is_dir() ), $dir->children();

    @list = map { $_->relative($dir) } @list;
    return @list;
}

=method get( $file )

Retrieves file from storage.

=cut

sub get {
    my $self = shift;
    my ($file) = @_;

    return $self->dir->file($file)->slurp();
}

=method put( $change, $file => $content, ... )

Adds files to storage with a text describing the change.

=cut

sub put {
    my $self = shift;
    my ( $change, %files ) = @_;

    my $dir = $self->dir;

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

=method delete( $change, $file, ... )

Removes files from storage.

=cut

sub delete {
    my $self = shift;
    my $change = shift;

    my @files = map { $self->dir->file($_)->stringify() } @_;

    $self->_git->rm(@files) if @files;
    $self->_git->commit( { message => $change, all => !@files }, @files );
}

=for Pod::Coverage pack unpack

Required methods in status for MooseX::Storage that don't perform any action
since the storage backend does not support serialization.

=cut

sub pack   { }
sub unpack { }

1;
