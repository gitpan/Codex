package Codex::Rule;
use strict;
use Codex::Operator;

my %builtin = map +($_->[0] => __PACKAGE__->new_builtin(@$_)), (
	[ 'conditional proof' => \&b_conditional ],
	[ 'proof by induction' => \&b_induction ],
	[ 'combine' => \&b_combine ],
	[ 'symmetry' => \&b_symmetry ],
	[ 'modus ponens' => \&b_ponens ],
	[ 'double implication' => \&b_doubleimp ],
	[ 'tautology' => \&b_tautology ],
	[ 'substitution' => \&b_substitute ],
	[ 'conjunction' => \&b_conjunction ],
);

my $opeq = Codex::Operator->builtin('equals');
my $opimpl = Codex::Operator->builtin('implies');
my $opand = Codex::Operator->builtin('and');

sub new {
	my($proto, $lname, $name, $expr) = @_;
	bless {
		'lname' => $lname,
		'name' => $name,
		'expr' => $expr,
	}, ref($proto) || $proto;
}

sub new_builtin {
	my($proto, $name, $sub) = @_;
	+{ builtin => 1, name => $name, sub => $sub };
}

sub lname { shift->{'lname'} }
sub name { shift->{'name'} }
sub expr { shift->{'expr'} }
sub text { shift->expr->text }
sub type { 'axiom' }

sub do_builtin {
	my $self = shift;
	&{ $self->{'sub'} }($self, @_);
}

sub builtin {
	my($proto, $name, $lname) = @_;
	return $proto->{'builtin'} if ref $proto;
	my $self = $builtin{$name} or return;
	bless {
		'lname' => $lname,
		%$self,
	}, ref($proto) || $proto;
}

sub b_conditional {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my($left, $right) = $deriv->cpderive(@$args);
		Codex::Expr->construct($opimpl, [ $left, $right ]);
	} else {
		die "b_conditional: '$type' not written";
	}
}

sub b_induction {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my($zero, $rule) = map $deriv->derive($_), @$args;
		return $deriv->error("Induction: arg2 must imply")
				unless $rule->op == $opimpl;
		my($prime, $second) = @{ $rule->args };
		my $ztext = $zero->text;
		my $ezero = Codex::Expr->construct('0');
		foreach my $var (@{ $prime->vars }) {
			my $e = $prime->transform(+{ $var => $ezero })
				or return $deriv->error("Induction panic: transform");
			next unless $e->text eq $ztext;
			my $esucc = Codex::Expr->new($deriv->codex, "$var + 1")
				or return $deriv->error("Induction panic: construct");
			$e = $prime->transform(+{ $var => $esucc })
				or return $deriv->error("Induction panic: transform succ");
			$e->text eq $second->text
				or return $deriv->error("Induction: arg2 RHS does not fit");
			return $prime;
		}
		$deriv->error("Couldn't find a variable to transform");
	} else {
		die "b_induction: '$type' not written";
	}
}

sub b_combine {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my($left, $right) = map $deriv->derive($_), @$args;
		foreach ([ $left, $right ], [ $right, $left ]) {
			my($a, $b) = @$_;
			if ($a->op == $opeq) {
				if ($a->args->[0]->text eq $b->text) {
					return $a->args->[1];
				} elsif ($a->args->[1]->text eq $b->text) {
					return $a->args->[0];
				}
			}
		}
		return $deriv->error("Combine: no primary match")
				unless $left->op == $opeq && $right->op == $opeq;
		foreach my $a ($left->args, [ reverse @{ $left->args } ]) {
			foreach my $b ($right->args, [ reverse @{ $right->args } ]) {
				next unless $a->[0]->text eq $b->[0]->text;
				return Codex::Expr->construct($opeq, [ $a->[1], $b->[1] ]);
			}
		}
		$deriv->error(sprintf "Combine: no secondary match '%s' ~ '%s'",
				$left->text, $right->text);
	} else {
		die "b_combine: '$type' not written";
	}
}

sub b_symmetry {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my $e = $deriv->derive($args->[0]);
		return $deriv->error("Symmetry: must be equals") unless $e->op == $opeq;
		Codex::Expr->construct($opeq, [ reverse @{ $e->args } ]);
	} else {
		die "b_symmetry: '$type' not written";
	}
}

sub b_ponens {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my($left, $right) = map $deriv->derive($_), @$args;
		return $deriv->error("mp: arg1 must imply") unless $left->op == $opimpl;
		return $deriv->error("mp: args must match")
				unless $left->args->[0]->text eq $right->text;
		$left->args->[1];
	} else {
		die "b_ponens: '$type' not written";
	}
}

sub b_doubleimp {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my($left, $right) = map $deriv->derive($_), @$args;
		return $deriv->error("double impl: args must imply")
				unless $left->op == $opimpl && $right->op == $opimpl;
		return $deriv->error("double impl: args must match")
				unless $left->args->[1]->text eq $right->args->[0]->text
						&& $left->args->[0]->text eq $right->args->[1]->text;
		Codex::Expr->construct($opeq, $left->args);
	} else {
		die "b_doubleimp: '$type' not written";
	}
}

sub b_tautology {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(expr) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		Codex::Expr->construct($opeq, [ $args->[0], $args->[0] ]);
	} else {
		die "b_tautology: '$type' not written";
	}
}

sub b_substitute {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line number) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		my($left, $right, $index) = @$args;
		$_ = $deriv->derive($_) foreach $left, $right;
		return $deriv->error("subst: arg2 must equal")
				unless $right->op == $opeq;
		my($old, $new) = @{ $right->args };
		if ($index < 0) {
			($old, $new) = ($new, $old);
			$index = -$index;
		}
		$left->swap($deriv->codex, $old, $new, $index);
	} else {
		die "b_substitute: '$type' not written";
	}
}

sub b_conjunction {
	my($self, $type) = (shift, shift);
	if ($type eq 'args') {
		[ qw(line line) ];
	} elsif ($type eq 'derive') {
		my($deriv, $args) = @_;
		Codex::Expr->construct($opand, [ map $deriv->derive($_), @$args ]);
	} else {
		die "b_conjunction: '$type' not written";
	}
}

1;
