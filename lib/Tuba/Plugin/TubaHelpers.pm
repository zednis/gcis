=head1 NAME

Tuba::Plugin::TubaHelpers -- various helpers

=head1 SYNOPSIS

app->plugin( 'tuba_helpers')

=cut

package Tuba::Plugin::TubaHelpers;
use Mojo::Base qw/Mojolicious::Plugin/;
use Time::Duration qw/ago/;
use List::Util qw/min/;
use Date::Parse qw/str2time/;
use Tuba::Util qw/get_config/;
use Tuba::Log;

#
# Usage :
#   include_first [ 'foo/bar', 'bar' ] => ...
# Copy/pasted from _include
#
sub _include_first {
  my $self     = shift;
  my $template = @_ % 2 ? shift : [];
  my $args     = {@_};

  my @templates = @$template;

  for my $template (@templates) {

      $args->{template} = $template if defined $template;

      # "layout" and "extends" can't be localized
      my $layout  = delete $args->{layout};
      my $extends = delete $args->{extends};

      # Localize arguments
      my @keys = keys %$args;
      local @{$self->stash}{@keys} = @{$args}{@keys};

      my $done = $self->render_maybe(partial => 1, layout => $layout, extend => $extends);
      return $done if $done;
    }

    return;
}

#
# Usage _look_similar($a,$b)
# Do $a and $b look similar?
#
sub _look_similar {
    my ($x,$y) = @_;
    $x //= '';
    $y //= '';
    s/^\s+// for ($x,$y);
    s/\s+$// for ($x,$y);
    return $x eq $y;
}

sub register {
    my ($self, $app, $conf) = @_;

    my $supported_formats = $conf->{supported_formats};

    $app->helper(base => sub {
        my $c = shift;
        my $base = $c->url_for('index')->path;
        $base =~ s[/$][];
        return $base;
    } );
    $app->helper(obj_link => sub {
            my $c = shift;
            my $obj = shift;
            return "" unless defined($obj);
            my $val = $obj->stringify(@_) || '[missing '.$obj->moniker.']';
            my $uri = $obj->uri($c);
            return $val unless $uri;
            return $c->link_to($val, $uri );
        } );
    $app->helper(obj_link_to => sub {
            my $c = shift;
            my $obj = shift;
            my $tab = shift;
            my $uri = $obj->uri($c,{ tab => $tab });
            return $c->link_to($uri, @_ );
        });
    $app->helper(obj_uri_for => sub {
            my $c = shift;
            my $obj = shift or return "";
            my $tab = shift;
            return $obj->uri($c,{ tab => $tab });
        });

    $app->helper(format_ago => sub {
            my $c = shift;
            my $date = shift;
            return ago(time - str2time($date), 1);
        });
    $app->helper(current_resource => sub {
            my $c = shift;
            if (my $cached = $c->stash('_current_resource')) {
                return $cached;
            }
            my $str = $c->req->url->clone->to_abs;
            for my $format (@$supported_formats) {
                $str =~ s/\.$format$// and last;
            }
            $c->stash('_current_resource' => $str);
            $str;
        });
    $app->helper(rdf_resource => sub {
            my $c = shift;
            my $frag = shift;
            return qq[http://www.w3.org/1999/02/22-rdf-syntax-ns#$frag]
        });
    $app->helper(property_to_iri => sub {
            my $c = shift;
            my $prop = shift;
            if ($prop =~ /^(prov):(.*)$/) {
                return qq[http://www.w3.org/ns/$1#$2];
            }
            if ($prop =~ /^(dc):(.*)$/) {
                return qq[http://purl.org/$1/terms/$2];
            }
            return $prop;
        });
    $app->helper(all_reports => sub {
            return @{ Tuba::DB::Object::Report::Manager->get_objects(all => 1, sort_by => 'identifier') };
        });
    $app->helper(default_report => sub {
            my $c = shift;
            my $obj;
            $obj = Tuba::DB::Object::Report->new(identifier => 'nca3')->load(speculative => 1) and return $obj;
            $obj = Tuba::DB::Object::Report->new(identifier => 'nca3draft')->load(speculative => 1) and return $obj;
            return Tuba::DB::Object::Report->new(identifier => 'no default report');
        });
    $app->helper(current_report => sub {
            my $c = shift;
            my $identifier = shift || $c->stash('report_identifier') || $c->session('report_identifier') || 'nca3draft';
            $c->session(report_identifier => $identifier);
            my $obj = Tuba::DB::Object::Report->new(identifier => $identifier);
            $obj->load(speculative => 1) and return $obj;
            $obj = Tuba::DB::Object::Report->new(identifier => 'nca3');
            $obj->load(speculative => 1) and $obj->_public and return $obj;
            return Tuba::DB::Object::Report->new(identifier => 'no report');
        });
    $app->helper(current_chapter => sub {
            my $c = shift;
            my $report = $c->current_report;
            return unless $report && $report->identifier ne 'no report';
            my $chapter_identifier = $c->stash('chapter_identifier') or return;
            my $chapter = Tuba::DB::Object::Chapter->new(identifier => $chapter_identifier, report_identifier => $report->identifier);
            $chapter->load(speculative => 1) or return;
            return $chapter;
        });
    $app->helper(elide => sub {
            my $c = shift;
            my $str = shift;
            my $len = shift or die "missing length";
            return $str if !$str || length($str) < $len;
            return substr($str,0,$len-3).'...';
        });
    $app->helper(labelize => sub {
            my $c = shift;
            my $str = shift;
            # Return a label for a database column.
            $str =~ s/_identifier//;
            $str =~ s/_dt$/_date/;
            $str =~ s/_code//;
            $str =~ s/_/ /g;
            return $str;
        });
    $app->helper(render_partial_ttl => sub {
            my $c = shift;
            my $table = shift || die "need table";
            return $c->render_maybe(partial => 1, format => 'ttl', template => "$table/object")
                || $c->render(partial => 1, format => 'ttl', template => "object");
        });
    $app->helper(render_ttl_as => sub {
            my $c = shift;
            my $ttl = shift;
            my $format = shift;
            my $conv = Tuba::Converter->new(
                    ttl  => $ttl,
                    base => $c->req->url->base->to_abs
                );
            $c->render( data => $conv->output( format => $format ));
        });
    $app->helper(render_partial_ttl_as => sub {
            my $c = shift;
            my $table = shift;
            my $format = shift;
            my $ttl = $c->render_partial_ttl($table);
            $c->render_ttl_as($ttl,$format);
        });
    $app->helper(detect_format => sub {
            # Taken from Mojolicious::Controller::respond_to
            my $c = shift;
            my $stash   = $c->stash;
            return $stash->{format} if $stash->{format}; 
            my @formats = @{$c->app->types->detect($c->req->headers->accept, $c->req->is_xhr)};
            unless (@formats) {
                my $format = $stash->{format} || $c->req->param('format');
                push @formats, $format ? $format : $app->renderer->default_format;
            }
            return $formats[0];
        });
    $app->helper(ontology_url => sub {
            my $c = shift;
            my $str = shift or return;
            my ($namespace,$frag) = split /:/, $str;
            return unless $namespace;
            my $gcis = $c->req->url->base->to_abs;
            $gcis =~ s/^https:/http:/;
            my %map = (
              prov   => q<http://www.w3.org/ns/prov#>,
              bibo   => q<http://purl.org/ontology/bibo/>,
              dc     => q<http://purl.org/dc/elements/1.1/>,
              dct    => q<http://purl.org/dc/terms/>,
              dctype => q<http://purl.org/dc/dcmitype/>,
              foaf   => q<http://xmlns.com/foaf/0.1/>,
              gcis   => qq<$gcis/gcis.owl#>,
              org    => q<http://www.w3.org/ns/org#>,
              prov   => q<http://www.w3.org/ns/prov#>,
              rdf    => q<http://www.w3.org/1999/02/22-rdf-syntax-ns#>,
              rdfs   => q<http://www.w3.org/2000/01/rdf-schema#>,
              xml    => q<http://www.w3.org/XML/1998/namespace>,
              xsd    => q<http://www.w3.org/2001/XMLSchema#>,
              cito   => #q<http://purl.org/spar/cito/>, # redirect ignores trailing part of url
                        q<http://www.essepuntato.it/lode/http://purl.org/spar/cito/>,
              biro   => #q<http://purl.org/spar/biro/>,
                        q<http://www.essepuntato.it/lode/http://purl.org/spar/biro/>,
            );
            my $base = $map{$namespace} or return;
            return $base.$frag;
        });

    $app->helper(uri => sub {
        my $c = shift;
        my $obj = shift or return "";
        return $obj->uri($c,{ tab => 'show' })->to_abs;
    });
    $app->helper(new_id => sub {
            state $id = 1;
            $id++; $id = 1 if $id > 1_000;
            $id;
        });
    $app->helper(min => sub {
            my $c = shift;
            return min(@_);
        });
    $app->helper(str_to_obj => sub {
         my $c = shift;
         my $str = shift;
         return $c->Tuba::Search::autocomplete_str_to_object($str);
     });
    $app->helper(uri_to_obj => sub {
         my $c = shift;
         my $uri = shift;

         # TODO clever generic way of doing this.
         my $obj;
         given ($uri) {
             m[^/report/([^/]+)$]                 and $obj = Tuba::DB::Object::Report->new(identifier => $1);
             m[^/report/([^/]+)/chapter/([^/]+)$] and $obj = Tuba::DB::Object::Chapter->new(report_identifier => $1, identifier => $2);
             m[^/report/([^/]+)/chapter/([^/]+)/figure/([^/]+)$]  and $obj = Tuba::DB::Object::Figure->new(report_identifier => $1, identifier => $3);
             m[^/report/([^/]+)/chapter/([^/]+)/finding/([^/]+)$] and $obj = Tuba::DB::Object::Finding->new(report_identifier => $1, identifier => $3);
             m[^/report/([^/]+)/chapter/([^/]+)/table/([^/]+)$]   and $obj = Tuba::DB::Object::Table->new(report_identifier => $1, identifier => $3);
             m[^/dataset/([^/]+)$]   and $obj = Tuba::DB::Object::Dataset->new(identifier => $1);
         }
         if ($obj && $obj->load(speculative => 1)) {
             return $obj;
         }
         $c->app->logger->warn("Could not identify $uri");
         return;
    });
    $app->helper(uri_to_pub => sub {
            my $c = shift;
            my $uri = shift;
            my $obj = $c->uri_to_obj($uri) or return;
            my $pub = $obj->get_publication(autocreate => 1);
            $pub->save(audit_user => $c->user) unless $pub->id;
            return $pub;
        });
    $app->helper(pl => sub {
            my $c = shift;
            my $str = shift;
            { person => 'people'}->{$str} || "${str}s";
        });
    $app->helper(db_labels => sub {
            my $c = shift;
            my $table = shift;
            return [ map [ $_->label, $_->identifier ],
                @{ $c->orm->{$table}->{mng}->get_objects(all => 1) } ];
        }); 
    $app->helper(include_first => \&_include_first);
    $app->helper(look_similar => sub { my $c = shift; _look_similar(@_);  });
    $app->helper(
      asset_location => sub {
        my $c        = shift;
        my $filename = shift;
        my $base = get_config('asset_path') or die "no asset_path configured";
        return "$base/$filename";
      }
    );

}

1;

