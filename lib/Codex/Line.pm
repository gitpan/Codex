package Codex::Line;
use strict;
use Codex::Expr;

sub new {
	my($proto, $codex, $expr) = @_;
	$expr = Codex::Expr->new($codex, $expr) unless ref $expr;
	$expr && bless { 'expr' => $expr }, ref($proto) || $proto;
}

sub expr { shift->{'expr'} }
sub builtin { 0 }
sub lname { shift->name }

sub dent {
	my $self = shift;
	$self->{'dent'} = shift if @_;
	$self->{'dent'} || 0;
}

sub type {
	my $self = shift;
	$self->{'type'} = shift if @_;
	$self->{'type'};
}

sub name {
	my $self = shift;
	$self->{'name'} = shift if @_;
	$self->{'name'};
}

sub derived {
	my $self = shift;
	$self->{'derived'} = shift if @_;
	$self->{'derived'};
}

sub text {
	my $self = shift;
	$self->{'text'} = $self->expr->text unless defined $self->{'text'};
	$self->{'text'};
}

1;
