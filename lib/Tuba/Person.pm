=head1 NAME

Tuba::Person : Controller class for people.

=cut

package Tuba::Person;
use Mojo::Base qw/Tuba::Controller/;
use Algorithm::Permute;
use Tuba::DB::Objects qw/-nicknames/;

sub list {
    my $c = shift;
    my $objects = Persons->get_objects;
    $_->load_foreign for @$objects;
    $c->respond_to(
        json => sub { shift->render(json => [ map $_->as_tree, @$objects ]) },
        html => sub { shift->render(template => 'person/objects', meta => Person->meta, objects => $objects ) }
    );
}

sub show {
    my $c = shift;
    my $identifier = $c->stash('person_identifier');
    my $person =
      Person->new( id => $identifier )
      ->load( speculative => 1, with => [qw/contributor/] )
      or return $c->render_not_found;

    $c->stash(object => $person);
    $c->stash(meta => Person->meta);
    return $c->SUPER::show(@_);
}

sub redirect_by_name {
    my $c = shift;
    my $name = $c->stash('name');
    my @pieces = split /-/, $name;
    my $p = Algorithm::Permute->new(\@pieces);
    my @query;
    while (my @res = $p->next) {
        push @query, ( name => { ilike => '%'.(join '%', @res).'%' } );
    }
    my $found = Persons->get_objects(query => [ or => \@query ], limit => 10 );
    return $c->render_not_found unless @$found;
    if ($found && @$found==1) {
        return $c->redirect_to('show_person', { person_identifier => $found->[0]->id } );
    }

    return $c->render(people => $found);
}

1;
