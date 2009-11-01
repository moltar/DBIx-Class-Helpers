package DBIx::Class::Helper::JoinTable;

use strict;
use warnings;

# ABSTRACT: Easily set up join tables with DBIx::Class

use DBIx::Class::Helpers::Util 'get_namespace_parts';
use Lingua::EN::Inflect ();

BEGIN {
    our $has_camel_case;

    sub _has_camel_case {
        return $has_camel_case if defined $has_camel_case;

        $has_camel_case = 0;
        eval {
            require String::CamelCase;
            $has_camel_case = 1;
        };

        return $has_camel_case;
    }
}

sub _pluralize {
   my ($self, $original) = @_;
   return join q{_}, split /\s+/,
      Lingua::EN::Inflect::PL(join q{ }, split /_/, $original);
}

sub _defaults {
   my ($self, $params) = @_;

   $params->{namespace}       ||= [ get_namespace_parts($self) ]->[0];
   if (_has_camel_case) {
      $params->{left_method}  ||= String::CamelCase::decamelize($params->{left_class});
      $params->{right_method} ||= String::CamelCase::decamelize($params->{right_class});
      $params->{self_method}  ||= String::CamelCase::decamelize($self);
   }
   $params->{left_method_plural}  ||= $self->_pluralize($params->{left_method});
   $params->{right_method_plural} ||= $self->_pluralize($params->{right_method});
   $params->{self_method_plural}  ||= $self->_pluralize($params->{self_method});

   return $params;
}

sub join_table {
   my ($self, $params) = @_;

   $self->set_table($params);
   $self->add_join_columns($params);
   $self->generate_relationships($params);
   $self->generate_primary_key($params);
}

sub generate_primary_key {
   my ($self, $params) = @_;

   $self->_defaults($params);
   $self->set_primary_key("$params->{left_method}_id", "$params->{right_method}_id");
}

sub generate_has_manys {
   my ($self, $params) = @_;

   $params = $self->_defaults($params);
   "$params->{namespace}::$params->{left_class}"->has_many(
      $params->{self_method} =>
      $self,
      "$params->{left_method}_id"
   );

   "$params->{namespace}::$params->{right_class}"->has_many(
      $params->{self_method} =>
      $self,
      "$params->{right_method}_id"
   );
}

sub generate_many_to_manys {
   my ($self, $params) = @_;

   $params = $self->_defaults($params);
   "$params->{namespace}::$params->{left_class}"->many_to_many(
      $params->{right_method_plural} =>
      $params->{right_class},
      "$params->{self_method}"
   );

   "$params->{namespace}::$params->{right_class}"->many_to_many(
      $params->{left_method_plural} =>
      $params->{left_class},
      "$params->{self_method}"
   );
}

sub generate_relationships {
   my ($self, $params) = @_;

   $params = $self->_defaults($params);
   $self->belongs_to(
      $params->{left_method} =>
      "$params->{namespace}::$params->{left_class}",
      "$params->{left_method}_id"
   );
   $self->belongs_to(
      $params->{right_method} =>
      "$params->{namespace}::$params->{right_class}",
      "$params->{right_method}_id"
   );
}

sub set_table {
   my ($self, $params) = @_;

   $self->table("$params->{left_class}_$params->{right_class}");
}

sub add_join_columns {
   my ($self, $params) = @_;

   $params = $self->_defaults($params);
   $self->add_columns(
      "$params->{left_method}_id" => {
         data_type         => 'integer',
         is_nullable       => 0,
         is_numeric        => 1,
      },
      "$params->{right_method}_id" => {
         data_type         => 'integer',
         is_nullable       => 0,
         is_numeric        => 1,
      },
   );
}

1;

=pod

=head1 SYNOPSIS

 package MyApp::Schema::Result::Foo_Bar;

 __PACKAGE__->load_components(qw{Helper::JoinTable Core});

 __PACKAGE__->join_table({
    left_class   => 'Foo',
    left_method  => 'foo',
    right_class  => 'Bar',
    right_method => 'bar',
 });

 # the above is the same as:

 __PACKAGE__->table('Foo_Bar');
 __PACKAGE__->add_columns(
    foo_id => {
       data_type         => 'integer',
       is_nullable       => 0,
       is_numeric        => 1,
    },
    bar_id => {
       data_type         => 'integer',
       is_nullable       => 0,
       is_numeric        => 1,
    },
 );

 $self->set_primary_key(qw{foo_id bar_id});

 __PACKAGE__->belongs_to( foo => 'MyApp::Schema::Result::Foo' 'foo_id');
 __PACKAGE__->belongs_to( bar => 'MyApp::Schema::Result::Bar' 'bar_id');

=head1 METHODS

All the methods take a configuration hashref that looks like the following:

 {
    left_class          => 'Foo',
    left_method         => 'foo',     # see L</NOTE>
    left_method_plural  => 'foos',    # see L</NOTE>, not required, used for
                                      # many_to_many rel name in right_class
                                      # which is not generated by default
    right_class         => 'Bar',
    right_method        => 'bar',     # see L</NOTE>
    right_method_plural => 'bars',    # see L</NOTE>, not required, used for
                                      # many_to_many rel name in left_class
                                      # which is not generated by default
    namespace           => 'MyApp',   # default is guessed via *::Foo
    self_method         => 'foobars', # not required, used for setting the name of the
                                      # join table's relationship in a has_many
                                      # which is not generated by default
 }

=head2 join_table

This is the method that you probably want.  It will set your table, add
columns, set the primary key, and set up the relationships.

=head2 add_join_columns

Adds two non-nullable integer fields named C<"${left_method}_id"> and
C<"${right_method}_id"> respectively.

=head2 generate_has_manys

Sets C<"${left_method}_id"> and C<"${right_method}_id"> to be the primary key.

=head2 generate_primary_key

Sets C<"${left_method}_id"> and C<"${right_method}_id"> to be the primary key.

=head2 generate_relationships

This adds relationships to C<"${namespace}::Schema::Result::$left_class"> and
C<"${namespace}::Schema::Result::$left_class"> respectively.

=head2 set_table

This method sets the table to "${left_class}_${right_class}".

=head2 NOTE

This module uses L<String::CamelCase> to default the method names if it is
installed.  Currently it fails pod tests, so I'm not making it a requirement.
Also will use L<Lingua::EN::Inflect> for pluralization.

