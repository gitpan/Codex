package Codex::Proof;
use strict;
use Errors;
use vars qw(@ISA);
@ISA = qw(Errors);

use Command;
use Parser;
use Codex;
use Codex::Expr;
use Codex::Deriv;
use Codex::Line;
use Codex::Rule;

Command->newvar(@$_) foreach (
	[ 'text' => '(.*)', sub { pop } ],
	[ 'rbracket' => '(\])', sub { pop } ],
	[ 'number' => '(?<! \S )(\d+)(?= \s | $)', sub { pop } ],
	[ 'name' => '\b(\w+)\b', sub { pop } ],
	[ 'lname' => '\b(\w[\w\d]*)\b', sub { pop } ],
	[ 'expr' => '(?<! \S ) (.*) (?= \s | $)', sub { Codex::Expr->new(@_) } ],
	[ 'deriv' => Codex::Expr::re_bbal, sub { Codex::Deriv->new(@_) } ],
);
my @parse = map Command->new(@$_), (
	[ 'rp $rbracket', 0, 'end scope' ],
	[ 'rp $number $deriv $expr', 0, 'load derived line' ],
	[ 'rp $lname builtin $text', 0, 'load builtin axiom as $lname' ],
	[ 'rp $lname $name $expr', 0, 'load other axiom as $lname' ],
	[ 'rp $number scope $expr [', 0, 'load condition' ],
);

sub new {
	my($proto, $type, $name) = @_;
	my $self = bless {
		'parent' => $proto,
		'type' => $type,
		'name' => $name,
	}, __PACKAGE__;
	$self->load;
}

sub parent { shift->{'parent'} }
sub lemmas { shift->{'lemmas'} ||= [] }
sub lines { shift->{'lines'} ||= [] }
sub lookup { shift->{'lookup'} ||= +{} }
sub axioms { shift->{'axioms'} ||= [] }
sub parser { shift->{'parser'} }
sub operators {
	my $self = shift;
	$self->{'operators'} ||= $self->parent->operators;
}
sub lemma {
	my $self = shift;
	$self->{'lemma'} ||= do {
		my $ego = $self->parent->define($self->type);
		$ego && $ego->lemma($self->name);
	};
}
sub type {
	my $self = shift;
	$self->{'type'} ||= die "panic: no type\n";		# $self->lemma->type;
}
sub name {
	my $self = shift;
	$self->{'name'} ||= die "panic: no name\n";		# $self->lemma->name;
}
sub filename {
	my $self = shift;
	sprintf "data/%s.%s", $self->type, $self->name;
}

sub conclusion {
	my $self = shift;
	$self->{'conclusion'} ||= $self->lemmas->[$#{ $self->lemmas }];
}

sub index {
	my($self, $find) = @_;
	[ grep {
		my $line = $self->lines->[$_];
		ref($line) && ($line == $find)
	} 0 .. $#{ $self->lines } ]->[0];
}

sub scope {
	my($self, $left, $right, $slack) = @_;
	my($lx, $rx) = map $self->index($_), $left, $right;
	$self->error("scope: panic, not my line"), return
		if grep !defined, $lx, $rx;
	return 0 if $rx > $lx;
	return 1 if $right->type eq 'axiom';
	my $rdent = $right->dent;
	++$rdent if $right->type eq 'scoped';
	return 1 if $rdent == 0;
	$slack ||= 0;
	return 0 if $rdent - $slack > $left->dent;
	for my $i ($lx + 1 .. $rx - 1) {
		return 0 if $rdent - $slack > $self->lines->[$i]->dent;
	}
	return 1;
}

sub text {
	my $self = shift;
	my $lines = [];
	push @$lines, map { $_->builtin
		? sprintf "%s builtin %s", $_->lname, $_->name
		: sprintf "%s %s %s", $_->lname, $_->name, $_->expr->text
	} @{ $self->axioms };
	push @$lines, '';
	my $dent = 0;
	foreach (0 .. $#{ $self->lemmas }) {
		my $line = $self->lemmas->[$_];
		my $newdent = $line->dent;
		my $text = "  " x $newdent . ($_ + 1);
		if ($line->type eq 'scoped') {
			push @$lines, '' unless $dent;
			push @$lines, sprintf "%s scope %s [", $text, $line->expr->text;
			$dent = ++$newdent;
		} else {
			while ($dent > $newdent) {
				--$dent;
				push @$lines, "  " x $dent . "]";
				push @$lines, '' unless $dent;
			}
			push @$lines, sprintf "%s (%s) %s",
				$text, $line->derived->text, $line->expr->text;
		}
	}
	join '', map "$_\n", @$lines;
}

sub test {
	my $self = shift;
	foreach (@{ $self->axioms }) {
		next if $_->builtin;
		my $type = $_->name;
		my $ego = $self->parent->define($type);
		unless ($ego) {
			$self->error("Can't locate definitions for $type");
			next;
		}
		my $text = $_->text;
		my $axiom;
		foreach (@{ $ego->lines }) {
			next unless ref($_) && $_->text eq $text;
			$axiom = $_;
			last;
		}
		unless ($axiom) {
			$self->error("Can't locate axiom '$text' in $type");
			next;
		}
		if ($ego->index($axiom) >= $ego->index($self->lemma)) {
			$self->error("Axiom '$text' appears after this lemma in $type");
		}
	}
	foreach (0 .. $#{ $self->lemmas }) {
		my $line = $self->lemmas->[$_];
		if ($line->type eq 'derived') {
			my $deriv = $line->derived;
			$deriv->test($line);
		} elsif ($line->type ne 'scoped' and $line->type ne 'outdent') {
			$self->error("Unknown derivation type '" . $line->type . "'");
		}
	}
	if (@{ $self->errors }) {
		$self->showerrors;
		0;
	} else {
		1;
	}
}

sub load {
	my $self = shift;
	my $p = $self->{'parser'}
			= Parser->newfile($self, \@parse, $self->filename, 'rp ');
	$self->error("Can't get parser for '".$self->filename."'\n") unless $p;
	my $result = 1;
	$result = $p->next while $result && !@{ $self->errors };
	$result = 0, $self->showerrors if @{ $self->errors };
	return if defined $result;
	warn sprintf "%s (lemma %s) %s\n", $self->type, $self->name,
			$self->conclusion->text;
	$self;
}

sub rp {
	my $self = shift;
	if (@_ == 1) {
		# [ 'rp $rbracket', 0, 'end scope' ]
		if (--$self->{'indent'} < 0) {
			$self->error("Too many outdents");
			$self->parser->quit;
		}
	} elsif (@_ == 2) {
		if (ref $_[1]) {
			# [ 'rp $number scope $expr [', 0, 'load condition' ]
			my($index, $expr) = @_;
			if ($index - 1 != @{ $self->lemmas }) {
				warn("Index $index out of order");
				# no quit
			}
			my $o = Codex::Line->new($self, $expr);
			if ($o) {
				$o->dent($self->{'indent'}++);
				$o->type('scoped');
				$o->name($index);
				push @{ $self->lemmas }, $o;
				push @{ $self->lines }, $o;
				$self->lookup->{$index} = $o;
			} else {
				$self->error("Couldn't create new scoped line");
				$self->parser->quit;
			}
		} else {
			# [ 'rp $lname builtin $text', 0, 'load builtin axiom as $lname' ]
			my($lname, $name) = @_;
			my $o = Codex::Rule->builtin($name, $lname);
			if ($o) {
				push @{ $self->axioms }, $o;
				push @{ $self->lines }, $o;
				$self->lookup->{$lname} = $o;
			} else {
				$self->error("Not a builtin rule '$name'");
				$self->parser->quit;
			}
		}
	} elsif (@_ == 3) {
		if (ref $_[1]) {
			# [ 'rp $number $deriv $expr', 0, 'load derived line' ]
			my($index, $deriv, $expr) = @_;
			if ($index - 1 != @{ $self->lemmas }) {
				warn("Index $index out of order");
				# no quit
			}
			my $o = Codex::Line->new($self, $expr);
			if ($o) {
				$o->derived($deriv);
				$o->dent($self->{'indent'});
				$o->type('derived');
				$o->name($index);
				push @{ $self->lemmas }, $o;
				push @{ $self->lines }, $o;
				$self->lookup->{$index} = $o;
			} else {
				$self->error("Couldn't create new line for $index");
				$self->parser->quit;
			}
		} else {
			# [ 'rp $lname $name $expr', 0, 'load other axiom as $lname' ]
			my($lname, $type, $expr) = @_;
			my $o = Codex::Rule->new($lname, $type, $expr);
			if ($o) {
				push @{ $self->axioms }, $o;
				push @{ $self->lines }, $o;
				$self->lookup->{$lname} = $o;
			} else {
				$self->error("Couldn't create new rule for $lname");
				$self->parser->quit;
			}
		}
	} else {
		$self->error("rp: unexpected number of arguments ".@_);
		return;
	}
}

1;
