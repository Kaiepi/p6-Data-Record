use v6.d;
use MetamodelX::RecorderHOW;
use MetamodelX::RecordTemplateHOW;
use Data::Record::Instance;
use Data::Record::Exceptions;

#|[ Iterator for tuples (lists of fixed length) that are to become records.
    Typechecks the list's values and coerces any record fields along the way. ]
my class TupleIterator does Iterator {
    has Mu         $.type      is required;
    has Str:D      $.mode      is required;
    has Str:D      $.operation is required;
    has Iterator:D $.fields    is required;
    has Iterator:D $.values    is required;
    has Int:D      $.arity     is required;
    has Int:D      $.count     = 0;

    submethod BUILD(::?CLASS:D: Mu :$!type! is raw, :$!mode!, :$!operation!, :$fields! is raw, :$values! is raw --> Nil) {
        $!fields := $fields.iterator;
        $!values := $values.iterator;
        $!arity  := $fields.elems;
    }

    method new(::?CLASS:_: Mu $type is raw, $mode, $operation, $fields is raw, $values is raw --> ::?CLASS:D) {
        self.bless: :$type, :$mode, :$operation, :$fields, :$values
    }

    method pull-one(::?CLASS:D:) is raw {
        self."$!mode"($!fields.pull-one)
    }

    method is-lazy(::?CLASS:D: --> Bool:D) {
        $!values.is-lazy
    }

    #|[ The list must have an arity equal to the tuple type's and all values
        must typecheck as their corresponding fields, otherwise an exception
        will be thrown. ]
    method wrap(::?CLASS:D: Mu $field is raw) is raw {
        LEAVE $!count++;
        self.map-one: $field, $!values.pull-one, :guard<more>, :keep<missing>
    }

    #|[ The list must have an arity greater than or equal to the tuple type; if
        it's greater, extraneous values will be stripped. If any values are
        missing or values corresponding to fields don't typecheck, an exception
        will be thrown. ]
    method consume(::?CLASS:D: Mu $field is raw) is raw {
        LEAVE $!count++;
        self.map-one: $field, $!values.pull-one, :guard<less>, :keep<missing>
    }

    #|[ The list must have an arity lesser than or equal to the tuple type's;
        if it's lesser, missing values will be stubbed (if possible).  If any
        values don't typecheck as their corresponding fields, an exception will
        be thrown. ]
    method subsume(::?CLASS:D: Mu $field is raw) is raw {
        LEAVE $!count++;
        self.map-one: $field, $!values.pull-one, :guard<more>, :keep<coercing>
    }

    #|[ Coerces a list. Arity does not matter; missing values are stubbed (if
        possible) and extraneous values are stripped. If any values don't
        typecheck as their corresponding fields, an exception will be thrown. ]
    method coerce(::?CLASS:D: Mu $field is raw) is raw {
        LEAVE $!count++;
        self.map-one: $field, $!values.pull-one, :guard<less>, :keep<coercing>
    }

    method map-one(::?CLASS:D: Mu $field is raw, Mu $value is raw, :$guard!, :$keep!) is raw {
        $field =:= IterationEnd
          ?? self."guard-$guard"($field, $value)
          !! $value =:= IterationEnd
            ?? self."keep-$keep"($field, $value)
            !! Metamodel::Primitives.is_type($value, Data::Record::Instance:U) || !$field.ACCEPTS($value)
              ?? X::Data::Record::TypeCheck.new(:$!operation, :expected($field), :got($value)).throw
              !! $value
    }

    method guard-more(Mu $field is raw, Mu $value is raw --> IterationEnd) {
        X::Data::Record::Extraneous.new(
            :$!operation, :$!type, :what<index>, :key($!count), :$value
        ).throw unless $value =:= IterationEnd;
    }

    method guard-less(Mu, Mu --> IterationEnd) { }

    method keep-missing(Mu $field is raw, Mu $value is raw --> IterationEnd) {
        X::Data::Record::Missing.new(
            :$!operation, :$!type, :what<index>, :key($!count), :$field
        ).throw;
    }

    method keep-coercing(Mu $field is raw, Mu $value is raw --> Mu) is raw {
        X::Data::Record::Definite.new(
            :$!type, :what<index>, :key($!count), :value($field)
        ).throw if $field.HOW.archetypes.definite && $field.^definite;
        $field
    }
}

class Data::Record::Tuple does Data::Record::Instance[List] does Iterable does Positional {
    has @!record;

    submethod BUILD(::?CLASS:D: :@record --> Nil) {
        @!record := @record;
    }

    multi method new(::?CLASS:_: List:D $original is raw --> ::?CLASS:D) {
        my @record := self.wrap: $original;
        @record.elems unless @record.is-lazy; # Reify eager lists for eager typechecking.
        self.bless: :@record
    }
    multi method new(::?CLASS:_: List:D $original is raw, Bool:D :consume($)! where ?* --> ::?CLASS:D) {
        my @record := self.consume: $original;
        @record.elems unless @record.is-lazy; # Reify eager lists for eager typechecking.
        self.bless: :@record
    }
    multi method new(::?CLASS:_: List:D $original is raw, Bool:D :subsume($)! where ?* --> ::?CLASS:D) {
        my @record := self.subsume: $original;
        @record.elems unless @record.is-lazy; # Reify eager lists for eager typechecking.
        self.bless: :@record
    }
    multi method new(::?CLASS:_: List:D $original is raw, Bool:D :coerce($)! where ?* --> ::?CLASS:D) {
        my @record := self.coerce: $original;
        @record.elems unless @record.is-lazy; # Reify eager lists for eager typechecking.
        self.bless: :@record
    }

    method wrap(::THIS ::?CLASS:_: ::T List:D $original is raw --> List:D) {
        T.from-iterator: TupleIterator.new: THIS, 'wrap', 'tuple reification', @.fields, $original
    }

    method consume(::THIS ::?CLASS:_: ::T List:D $original is raw --> List:D) {
        T.from-iterator: TupleIterator.new: THIS, 'consume', 'tuple reification', @.fields, $original
    }

    method subsume(::THIS ::?CLASS:_: ::T List:D $original is raw --> List:D) {
        T.from-iterator: TupleIterator.new: THIS, 'subsume', 'tuple reification', @.fields, $original
    }

    method coerce(::THIS ::?CLASS:_: ::T List:D $original is raw --> List:D) {
        T.from-iterator: TupleIterator.new: THIS, 'coerce', 'tuple reification', @.fields, $original
    }

    method fields(::?CLASS:_: --> List:D) { self.^fields }

    method record(::?CLASS:D: --> List:D) { @!record }

    method unrecord(::?CLASS:D: --> List:D) {
        @!record.WHAT.from-iterator: @!record.map(&unrecord).iterator
    }
    proto sub unrecord(Mu --> Mu) {*}
    multi sub unrecord(Data::Record::Instance:D \recorded --> Mu) {
        recorded.unrecord
    }
    multi sub unrecord(Mu \value --> Mu) is raw {
        value
    }

    multi method raku(::?CLASS:U: --> Str:D) {
        my Str:D $raku = '<@ ' ~ @.fields.map(*.raku).join(', ') ~ ' @>';
        my Str:D $name = self.^name;
        $raku ~= ":name('$name')" unless $name eq MetamodelX::RecordHOW::ANON_NAME;
        $raku
    }

    multi method ACCEPTS(::?CLASS:U: List:D $list is raw --> Bool:D) {
        # $list could be lazy, so we can't just .elems it to find out if it has
        # the correct arity. Instead, ensure the index for each of our fields
        # exists in $list and typechecks, then check if any extraneous values
        # exist.
        my Int:D $count = 0;
        for @.fields.kv -> Int:D $idx, Mu $field is raw {
            return False unless $list[$idx]:exists && $list[$idx] ~~ $field;
            $count++;
        }
        $list[$count]:!exists
    }

    method EXISTS-POS(::?CLASS:D: Int:D $pos --> Bool:D) {
        @!record[$pos]:exists
    }

    method AT-POS(::THIS ::?CLASS:D: Int:D $pos --> Mu) is raw {
        if @.fields[$pos]:!exists {
            die X::Data::Record::OutOfBounds.new:
                type => THIS,
                what => 'index',
                key  => $pos
        } else {
            @!record[$pos]
        }
    }

    method BIND-POS(::THIS ::?CLASS:D: Int:D $pos, Mu $value is raw --> Mu) is raw {
        my @fields := @.fields;
        if @fields[$pos]:!exists {
            die X::Data::Record::OutOfBounds.new:
                type => THIS,
                what => 'index',
                key  => $pos
        } else {
            self!field-op: 'binding', {
                @!record[$pos] := $_
            }, @fields[$pos], $value
        }
    }

    method ASSIGN-POS(::THIS ::?CLASS:D: Int:D $pos, Mu $value is raw --> Mu) is raw {
        my @fields := @.fields;
        if @fields[$pos]:!exists {
            die X::Data::Record::OutOfBounds.new:
                type => THIS,
                what => 'index',
                key  => $pos
        } else {
            self!field-op: 'assignment', {
               @!record[$pos] = $_
            }, @fields[$pos], $value
        }
    }

    method DELETE-POS(::THIS ::?CLASS:D: Int:D $pos --> Mu) is raw {
        die X::Data::Record::Immutable.new:
            operation => 'deletion',
            type      => THIS
    }

    method push(::THIS ::?CLASS:D: | --> Mu) {
        die X::Data::Record::Immutable.new:
            operation => 'push',
            type      => THIS
    }

    method pop(::THIS ::?CLASS:D: | --> Mu) {
        die X::Data::Record::Immutable.new:
            operation => 'pop',
            type      => THIS
    }

    method shift(::THIS ::?CLASS:D: | --> Mu) {
        die X::Data::Record::Immutable.new:
            operation => 'shift',
            type      => THIS
    }

    method unshift(::THIS ::?CLASS:D: | --> Mu) {
        die X::Data::Record::Immutable.new:
            operation => 'unshift',
            type      => THIS
    }

    method append(::THIS ::?CLASS:D: | --> Mu) {
        die X::Data::Record::Immutable.new:
            operation => 'append',
            type      => THIS
    }

    method prepend(::THIS ::?CLASS:D: | --> Mu) {
        die X::Data::Record::Immutable.new:
            operation => 'append',
            type      => THIS
    }

    method eager(::?CLASS:D: --> ::?CLASS:D) {
        @!record.is-lazy ?? self.new(@.record.eager) !! self
    }

    method lazy(::?CLASS:D: --> ::?CLASS:D) {
        @!record.is-lazy ?? self !! self.new(@.record.lazy)
    }

    method iterator(::?CLASS:D: --> Mu)  { @!record.iterator }
    method is-lazy(::?CLASS:D: --> Mu)   { @!record.is-lazy }
    method cache(::?CLASS:D: --> Mu)     { @!record.cache }
    method list(::?CLASS:D: --> Mu)      { self }
    method elems(::?CLASS:D: --> Mu)     { @!record.elems }
    method hash(::?CLASS:D: --> Mu)      { @!record.hash }
    method keys(::?CLASS:D: --> Mu)      { @!record.keys }
    method values(::?CLASS:D: --> Mu)    { @!record.values }
    method kv(::?CLASS:D: --> Mu)        { @!record.kv }
    method pairs(::?CLASS:D: --> Mu)     { @!record.pairs }
    method antipairs(::?CLASS:D: --> Mu) { @!record.antipairs }
}

multi sub circumfix:«<@ @>»(+@fields is raw, Str:_ :$name --> Mu) is export {
    MetamodelX::RecorderHOW[List].new_type(Data::Record::Tuple, @fields, :$name).^compose
}
multi sub circumfix:«<@ @>»(Block:D $block is raw, Str:_ :$name --> Mu) is export {
    MetamodelX::RecordTemplateHOW[List].new_type(Data::Record::Tuple, $block, :$name)
}

multi sub infix:«(><)»(List:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs
}
multi sub infix:«(><)»(Data::Record::Tuple:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs.record
}
multi sub infix:«(><)»(Data::Record::Tuple:U $lhs is raw, List:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs
}
multi sub infix:«(><)»(Data::Record::Tuple:U $lhs is raw, Data::Record::Tuple:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs.record
}

multi sub infix:«(<<)»(List:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs, :consume
}
multi sub infix:«(<<)»(Data::Record::Tuple:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs.record, :consume
}
multi sub infix:«(<<)»(Data::Record::Tuple:U $lhs is raw, List:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs, :subsume
}
multi sub infix:«(<<)»(Data::Record::Tuple:U $lhs is raw, Data::Record::Tuple:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs.record, :subsume
}

multi sub infix:«(>>)»(List:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs, :subsume
}
multi sub infix:«(>>)»(Data::Record::Tuple:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs.record, :subsume
}
multi sub infix:«(>>)»(Data::Record::Tuple:U $lhs is raw, List:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs, :consume
}
multi sub infix:«(>>)»(Data::Record::Tuple:U $lhs is raw, Data::Record::Tuple:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs.record, :consume
}

multi sub infix:«(<>)»(List:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs, :coerce
}
multi sub infix:«(<>)»(Data::Record::Tuple:D $lhs is raw, Data::Record::Tuple:U $rhs is raw --> Data::Record::Tuple:D) is export {
    $rhs.new: $lhs.record, :coerce
}
multi sub infix:«(<>)»(Data::Record::Tuple:U $lhs is raw, List:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs, :coerce
}
multi sub infix:«(<>)»(Data::Record::Tuple:U $lhs is raw, Data::Record::Tuple:D $rhs is raw --> Data::Record::Tuple:D) is export {
    $lhs.new: $rhs.record, :coerce
}

multi sub infix:<eqv>(List:D $lhs is raw, Data::Record::Tuple:D $rhs is raw --> Bool:D) is export {
    $lhs eqv $rhs.unrecord
}
multi sub infix:<eqv>(Data::Record::Tuple:D $lhs is raw, List:D $rhs is raw --> Bool:D) is export {
    $lhs.unrecord eqv $rhs
}
multi sub infix:<eqv>(Data::Record::Tuple:D $lhs is raw, Data::Record::Tuple:D $rhs is raw --> Bool:D) is export {
    $lhs.unrecord eqv $rhs.unrecord
}
