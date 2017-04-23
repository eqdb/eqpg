--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Drop databases
--

DROP DATABASE eqdb;




--
-- Drop roles
--

DROP ROLE eqdb;
DROP ROLE postgres;


--
-- Roles
--

CREATE ROLE eqdb;
ALTER ROLE eqdb WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 100 PASSWORD 'md564d44010a70520d4af7c2c4e08dc8c98';
CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'md5bed9ea18f44fe0aeb26a86b75fe6a725';






--
-- Database creation
--

CREATE DATABASE eqdb WITH TEMPLATE = template0 OWNER = postgres;
REVOKE CONNECT,TEMPORARY ON DATABASE eqdb FROM PUBLIC;
GRANT CONNECT ON DATABASE eqdb TO eqdb;
GRANT TEMPORARY ON DATABASE eqdb TO PUBLIC;
REVOKE CONNECT,TEMPORARY ON DATABASE template1 FROM PUBLIC;
GRANT CONNECT ON DATABASE template1 TO PUBLIC;


\connect eqdb

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.2
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plperl; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plperl WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plperl; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plperl IS 'PL/Perl procedural language';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET search_path = public, pg_catalog;

--
-- Name: expression_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE expression_type AS ENUM (
    'integer',
    'function',
    'generic'
);


ALTER TYPE expression_type OWNER TO postgres;

--
-- Name: keyword_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE keyword_type AS ENUM (
    'word',
    'acronym',
    'abbreviation',
    'symbol',
    'latex'
);


ALTER TYPE keyword_type OWNER TO postgres;

--
-- Name: operator_associativity; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE operator_associativity AS ENUM (
    'ltr',
    'rtl'
);


ALTER TYPE operator_associativity OWNER TO postgres;

--
-- Name: operator_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE operator_type AS ENUM (
    'prefix',
    'infix',
    'postfix'
);


ALTER TYPE operator_type OWNER TO postgres;

--
-- Name: step_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE step_type AS ENUM (
    'set',
    'copy_proof',
    'rule_normal',
    'rule_invert',
    'rule_mirror',
    'rule_revert',
    'rearrange'
);


ALTER TYPE step_type OWNER TO postgres;

--
-- Name: expr_match_rule(integer[], integer[], integer[], integer[], integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION expr_match_rule(integer[], integer[], integer[], integer[], integer[]) RETURNS boolean
    LANGUAGE plperl
    AS $_$
my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

my $expr_hash_mix = sub {
  my ($hash, $value) = @_;
  $hash = 0x1fffffff & ($hash + $value);
  $hash = 0x1fffffff & ($hash + ((0x0007ffff & $hash) << 10));
  $hash = $hash ^ ($hash >> 6);
  return $hash;
};

my $expr_hash_postprocess = sub {
  my ($hash) = @_;
  $hash = 0x1fffffff & ($hash + ((0x03ffffff & $hash) << 3));
  $hash = $hash ^ ($hash >> 11);
  return 0x1fffffff & ($hash + ((0x00003fff & $hash) << 15));
};

# Compute hash for the given part of the expression data array. Replacing all
# hashes that are in the mapping with the mapped hashes.
my $compute_mapped_hash;
$compute_mapped_hash = sub {
  my ($ptr, $mapping_hash, $data) = @_;

  my $hash = $data->[$ptr++];
  my $type = $data->[$ptr++];
  my $value = $data->[$ptr++];

  if (exists $$mapping_hash{$hash}) {
    return ($$mapping_hash{$hash}, $ptr);
  } elsif ($type == $EXPR_FUNCTION || $type == $EXPR_FUNCTION_GEN) {
    # Hash all arguments together.
    my $argc = $data->[$ptr];
    $ptr += 2;

    $hash = 0;
    $hash = $expr_hash_mix->($hash, $type);
    $hash = $expr_hash_mix->($hash, $value);

    while ($argc > 0) {
      $argc--;
      (my $arg_hash, $ptr) = $compute_mapped_hash->($ptr, $mapping_hash, $data);
      $hash = $expr_hash_mix->($hash, $arg_hash);
    }

    $hash = $expr_hash_postprocess->($hash);
    $hash = ($hash << 1) & 0x3fffffff;
    return ($hash, $ptr);
  } else {
    return ($hash, $ptr);
  }
};

# Evaluate function using the given mapping.
my $evaluate = sub {
  my ($ptr, $mapping_hash, $computable_ids, $data) = @_;
  my ($id_add, $id_sub, $id_mul, $id_neg) = @$computable_ids;

  # The stack consists of alternating values: (function ID, 0) or (integer, 1).
  my @stack;

  while (1) {
    my $hash = $data->[$ptr++];
    my $type = $data->[$ptr++];
    my $value = $data->[$ptr++];

    if ($type == $EXPR_SYMBOL_GEN || $type == $EXPR_INTEGER) {
      my $argument = $value; # Valid for $type == $EXPR_INTEGER.

      if ($type == $EXPR_SYMBOL_GEN) {
        if (exists($$mapping_hash{$hash})) {
          my $target = $$mapping_hash{$hash};

          # Reconstruct integer value.
          if ($target & 0x1 == 1) {
            $argument = $target >> 2;
            if (($target >> 1) & 0x1 == 1) {
              $argument = -$argument;
            }
          } else {
            # If the generic does not point to an integer, terminate.
            return (undef, $ptr);
          }
        } else {
          return (undef, $ptr);
        }
      }

      # We use the usefull fact that all computable functions have exactly
      # two arguments.
      # We can assume there are elements in the stack at this point since
      # this function is called with the pointer pointing to a function
      # first.
      if ($stack[-1] == 1) {
        # Collapse stack.
        do {
          pop(@stack);                    # Remove first argument flag [1].
          my $other = pop(@stack);        # Get other integer.
          pop(@stack);                    # Remove computation flag [0].
          my $computation = pop(@stack);  # Get computation ID.

          # Do computation.
          if ($computation == $id_add)    { $argument = $other + $argument; }
          elsif ($computation == $id_sub) { $argument = $other - $argument; }
          elsif ($computation == $id_mul) { $argument = $other * $argument; }
          elsif ($computation == $id_neg) { $argument = -$argument; }

        } while (@stack && $stack[-1] == 1);

        # If the stack is empty, return the result.
        if (!@stack) {
          return ($argument, $ptr);
        } else {
          push(@stack, $argument, 1);
        }
      } else {
        # This is the first argument of the lowest computation in the stack.
        push(@stack, $argument, 1);
      }
    } elsif ($type == $EXPR_FUNCTION) {
      if ($value == $id_add || $value == $id_sub ||
          $value == $id_mul || $value == $id_neg) {
        # Push function ID to stack.
        push(@stack, $value, 0);

        # Skip argument count and content-length (we know the argument length of
        # all computable functions ahead of time).
        $ptr += 2;

        # If this is the negation function, add a first argument here as an
        # imposter. This way the negation function can be integrated in the same
        # code as the binary operators.
        if ($value == $id_neg) {
          push(@stack, 0, 1);
        }
      } else {
        return (undef, $ptr);
      }
    } else {
      return (undef, $ptr);
    }
  }

  # This point will not be reached.
};

# Recursive expression pattern matching.
my $match_pattern;
$match_pattern = sub {
  my ($write_mapping, $internal_remap, $mapping_hash, $mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data) = @_;

  my $argc = 1; # arguments left to be processed.

  # Iterate through data untill out of arguments.
  # Returns success if loop completes. If a mismatch is found the function
  # should be terminated directly.
  while ($argc > 0) {
    $argc--;

    my $hash_t = $data[$ptr_t++];
    my $hash_p = $data[$ptr_p++];
    my $type_t = $data[$ptr_t++];
    my $type_p = $data[$ptr_p++];
    my $value_t = $data[$ptr_t++];
    my $value_p = $data[$ptr_p++];

    if ($type_p == $EXPR_SYMBOL_GEN) {
      if (!$write_mapping || exists($$mapping_hash{$hash_p})) {
        if ($$mapping_hash{$hash_p} != $hash_t) {
          return 0;
        }
      } else {
        $$mapping_hash{$hash_p} = $hash_t;
      }

      # Jump over function body.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }      
    } elsif ($type_p == $EXPR_FUNCTION_GEN) {
      if (!$write_mapping) {
        # Internal remapping.
        if ($internal_remap) {
          # Disallow generic functions in internal remapping.
          return 0;
        }

        # Retrieve pointers.
        my $ptrs = $$mapping_genfn{$value_p};
        my $mptr_t = $$ptrs[0];
        my $pattern_arg_hash = $$ptrs[2];
        my $pattern_arg_target_hash = $$mapping_hash{$pattern_arg_hash};

        # Compute hash for internal substitution.
        # Overhead of running this when there is no difference is minimal.
        my @result = $compute_mapped_hash->($ptr_p + 2, $mapping_hash, \@data);
        my $computed_hash = $result[0];

        # Deep compare if the computed hash is different.
        if ($computed_hash != $pattern_arg_target_hash) {
          # Temporarily add hash to mapping.
          my $old_hash = $$mapping_hash{$pattern_arg_target_hash};
          $$mapping_hash{$pattern_arg_target_hash} = $computed_hash;

          # Old expression is used as pattern, current expression as target.
          if (!$match_pattern->(0, 1, $mapping_hash, $mapping_genfn,
              $ptr_t - 3, $mptr_t, $computable_ids, @data)) {
            return 0;
          }

          # Restore old mapping.
          $$mapping_hash{$pattern_arg_target_hash} = $old_hash;
        } else {
          # Shallow compare.
          if ($$mapping_hash{$hash_p} != $hash_t) {
            return 0;
          }
        }
      } else {
        # Validate against existing mapping hash.
        if (exists $$mapping_hash{$hash_p}) {
          if ($$mapping_hash{$hash_p} != $hash_t) {
            return 0;
          }
        } else {
          $$mapping_hash{$hash_p} = $hash_t;

          # Add expression pointer to mapping for later use.
          # Both pointers point at the start of the expression.
          $$mapping_genfn{$value_p} = [$ptr_t - 3, $ptr_p - 3];
        }
      }

      # Jump over function body.
      # Generic functions operating on generic functions are actually bullshit.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }
      $ptr_p += 2 + $data[$ptr_p + 1];
    } elsif ($type_p == $EXPR_SYMBOL) {
      # Check interal remapping caused by generic functions.
      if ($internal_remap && exists $$mapping_hash{$hash_p}) {
        if ($$mapping_hash{$hash_p} != $hash_t) {
          return 0;
        } else {
          # The symbol is in the mapping and matches the given hash. It is
          # possible that the target is a function so now we need to jump over
          # its function body.
          if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
            $ptr_t += 2 + $data[$ptr_t + 1];
          }
        }
      } else {
        if ($type_t != $EXPR_SYMBOL || $value_t != $value_p) {
          return 0;
        }
      }
    } elsif ($type_p == $EXPR_FUNCTION) {  
      if ($type_t == $EXPR_FUNCTION) {
        if ($value_t == $value_p) {
          my $argc_t = $data[$ptr_t++];
          my $argc_p = $data[$ptr_p++];

          # Both functions must have the same number of arguments.
          if ($argc_t == $argc_p) {
            # Skip content-length.
            $ptr_t++;
            $ptr_p++;

            # Add argument count to the total.
            $argc += $argc_p;
          } else {
            # Different number of arguments.
            return 0;
          }
        } else {
          # Function IDs do not match.
          return 0;
        }
      } elsif (!$write_mapping && !$internal_remap && $type_t == $EXPR_INTEGER) {
        # Note: we do not run this during internal remapping to avoid
        # complicated cases with difficult behavior.

        # Check if pattern function can be evaluated to the same integer as the
        # target expression.
        my ($evaluated_value, $ptr_t) = $evaluate->($ptr_p - 3, $mapping_hash,
            $computable_ids, \@data);

        if (!defined($evaluated_value) || $value_t != $evaluated_value) {
          return 0;
        } else {
          # Jump over function body.
          $ptr_p += 2 + $data[$ptr_p + 1];
        }
      } else {
        # Expression is not also a function or an integer.
        return 0;
      }
    } elsif ($type_p == $EXPR_INTEGER) {
      # Integers are not very common in patterns. Therefore this is checked
      # last.
      if ($type_t != $EXPR_INTEGER || $value_t != $value_p) {
        return 0;
      }
    } else {
      # Unknown expression type.
      return 0;
    }
  }

  # Also return pointer value.
  return (1, $ptr_t, $ptr_p);
};

# Rule matching
# It is possible to put match_pattern inside this function for some very minimal
# gain (arguments do not have to be copied).
my $expr_match_rule = sub {
  my ($expr_left, $expr_right, $rule_left, $rule_right, $computable_ids) = @_;
  my (%mapping_hash, %mapping_genfn);
  my $ptr_t = 0;
  my $ptr_p = scalar(@$expr_left) + scalar(@$expr_right);
  my @data = (@$expr_left, @$expr_right, @$rule_left, @$rule_right);

  (my $result_left, $ptr_t, $ptr_p) = $match_pattern->(1, 0,
      \%mapping_hash, \%mapping_genfn, $ptr_t, $ptr_p, $computable_ids, @data);
  if (!$result_left) {
    return 0;
  }

  # Process generic function mapping.
  foreach my $ptrs (values %mapping_genfn) {
    my $mptr_t = $$ptrs[0];
    my $mptr_p = $$ptrs[1];

    # Get hash of first argument of pattern function.
    # This first argument should be generic.
    my $pattern_arg_hash = $data[$mptr_p + 5];
    push @$ptrs, $pattern_arg_hash;

    # If no target hash exists and the expression function has 1 argument, the
    # generic is mapped to that argument.
    if (!exists $mapping_hash{$pattern_arg_hash}) {
      if ($data[$mptr_t + 3] == 1) {
        # Map pattern argument to hash of first expression argument.
        my $hash = $data[$mptr_t + 5];
        $mapping_hash{$pattern_arg_hash} = $hash;
      } else {
        # Argument count not 1, and no target hash exists. So terminate.
        return 0;
      }
    }
  }

  my ($result_right) = $match_pattern->(0, 0, \%mapping_hash, \%mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data);
  return $result_right;
};

return $expr_match_rule->(@_);
$_$;


ALTER FUNCTION public.expr_match_rule(integer[], integer[], integer[], integer[], integer[]) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: definition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE definition (
    id integer NOT NULL,
    rule_id integer NOT NULL
);


ALTER TABLE definition OWNER TO postgres;

--
-- Name: definition_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE definition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE definition_id_seq OWNER TO postgres;

--
-- Name: definition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE definition_id_seq OWNED BY definition.id;


--
-- Name: descriptor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE descriptor (
    id integer NOT NULL
);


ALTER TABLE descriptor OWNER TO postgres;

--
-- Name: descriptor_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE descriptor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE descriptor_id_seq OWNER TO postgres;

--
-- Name: descriptor_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE descriptor_id_seq OWNED BY descriptor.id;


--
-- Name: expression; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE expression (
    id integer NOT NULL,
    data bytea NOT NULL,
    hash bytea NOT NULL,
    latex text,
    functions integer[] NOT NULL,
    node_type expression_type NOT NULL,
    node_value integer NOT NULL,
    node_arguments integer[] NOT NULL
);


ALTER TABLE expression OWNER TO postgres;

--
-- Name: expression_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE expression_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE expression_id_seq OWNER TO postgres;

--
-- Name: expression_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE expression_id_seq OWNED BY expression.id;


--
-- Name: function; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE function (
    id integer NOT NULL,
    subject_id integer NOT NULL,
    descriptor_id integer,
    generic boolean NOT NULL,
    rearrangeable boolean NOT NULL,
    argument_count smallint NOT NULL,
    keyword text,
    keyword_type keyword_type,
    latex_template text,
    CONSTRAINT function_argument_count_check CHECK ((argument_count >= 0)),
    CONSTRAINT function_check CHECK (((NOT generic) OR (argument_count < 2))),
    CONSTRAINT function_check1 CHECK ((NOT (rearrangeable AND (argument_count < 2)))),
    CONSTRAINT function_keyword_check CHECK ((keyword ~ '^[a-z]+[0-9]*$'::text)),
    CONSTRAINT function_latex_template_check CHECK (((latex_template = ''::text) IS NOT TRUE)),
    CONSTRAINT keyword_must_have_type CHECK ((((keyword IS NULL) AND (keyword_type IS NULL)) OR ((keyword IS NOT NULL) AND (keyword_type IS NOT NULL)))),
    CONSTRAINT must_have_keyword_or_template CHECK (((keyword IS NOT NULL) OR (latex_template IS NOT NULL))),
    CONSTRAINT non_generic_with_args_needs_name CHECK ((NOT ((NOT generic) AND (argument_count > 0) AND (descriptor_id IS NULL))))
);


ALTER TABLE function OWNER TO postgres;

--
-- Name: function_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE function_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE function_id_seq OWNER TO postgres;

--
-- Name: function_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE function_id_seq OWNED BY function.id;


--
-- Name: language; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE language (
    id integer NOT NULL,
    code text NOT NULL,
    CONSTRAINT language_code_check CHECK ((code ~ '^[a-z]{2}(_([a-zA-Z]{2}){1,2})?_[A-Z]{2}$'::text))
);


ALTER TABLE language OWNER TO postgres;

--
-- Name: language_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE language_id_seq OWNER TO postgres;

--
-- Name: language_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE language_id_seq OWNED BY language.id;


--
-- Name: operator; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE operator (
    id integer NOT NULL,
    function_id integer NOT NULL,
    precedence_level smallint NOT NULL,
    associativity operator_associativity NOT NULL,
    operator_type operator_type NOT NULL,
    "character" character(1) NOT NULL,
    editor_template text NOT NULL,
    CONSTRAINT operator_precedence_level_check CHECK ((precedence_level > 0))
);


ALTER TABLE operator OWNER TO postgres;

--
-- Name: operator_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE operator_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE operator_id_seq OWNER TO postgres;

--
-- Name: operator_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE operator_id_seq OWNED BY operator.id;


--
-- Name: proof; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE proof (
    id integer NOT NULL,
    first_step_id integer NOT NULL,
    last_step_id integer NOT NULL
);


ALTER TABLE proof OWNER TO postgres;

--
-- Name: proof_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE proof_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE proof_id_seq OWNER TO postgres;

--
-- Name: proof_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE proof_id_seq OWNED BY proof.id;


--
-- Name: rule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE rule (
    id integer NOT NULL,
    proof_id integer,
    left_expression_id integer NOT NULL,
    right_expression_id integer NOT NULL,
    left_array_data integer[] NOT NULL,
    right_array_data integer[] NOT NULL
);


ALTER TABLE rule OWNER TO postgres;

--
-- Name: rule_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rule_id_seq OWNER TO postgres;

--
-- Name: rule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE rule_id_seq OWNED BY rule.id;


--
-- Name: step; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE step (
    id integer NOT NULL,
    previous_id integer,
    expression_id integer NOT NULL,
    "position" smallint NOT NULL,
    step_type step_type NOT NULL,
    proof_id integer,
    rule_id integer,
    rearrange smallint[],
    CONSTRAINT step_position_check CHECK (("position" >= 0)),
    CONSTRAINT valid_type CHECK ((((previous_id = NULL::integer) AND (step_type = 'set'::step_type)) OR ((previous_id <> NULL::integer) AND (((step_type = 'copy_proof'::step_type) AND (proof_id IS NOT NULL)) OR ((step_type = 'rearrange'::step_type) AND (rearrange IS NOT NULL)) OR (rule_id IS NOT NULL)))))
);


ALTER TABLE step OWNER TO postgres;

--
-- Name: step_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE step_id_seq OWNER TO postgres;

--
-- Name: step_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE step_id_seq OWNED BY step.id;


--
-- Name: subject; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE subject (
    id integer NOT NULL,
    descriptor_id integer NOT NULL
);


ALTER TABLE subject OWNER TO postgres;

--
-- Name: subject_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE subject_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE subject_id_seq OWNER TO postgres;

--
-- Name: subject_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE subject_id_seq OWNED BY subject.id;


--
-- Name: translation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE translation (
    id integer NOT NULL,
    descriptor_id integer NOT NULL,
    language_id integer NOT NULL,
    content text NOT NULL,
    CONSTRAINT translation_content_check CHECK ((content ~ '^(?:[^\s]+ )*[^\s]+$'::text))
);


ALTER TABLE translation OWNER TO postgres;

--
-- Name: translation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE translation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE translation_id_seq OWNER TO postgres;

--
-- Name: translation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE translation_id_seq OWNED BY translation.id;


--
-- Name: definition id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition ALTER COLUMN id SET DEFAULT nextval('definition_id_seq'::regclass);


--
-- Name: descriptor id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY descriptor ALTER COLUMN id SET DEFAULT nextval('descriptor_id_seq'::regclass);


--
-- Name: expression id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression ALTER COLUMN id SET DEFAULT nextval('expression_id_seq'::regclass);


--
-- Name: function id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function ALTER COLUMN id SET DEFAULT nextval('function_id_seq'::regclass);


--
-- Name: language id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language ALTER COLUMN id SET DEFAULT nextval('language_id_seq'::regclass);


--
-- Name: operator id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator ALTER COLUMN id SET DEFAULT nextval('operator_id_seq'::regclass);


--
-- Name: proof id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof ALTER COLUMN id SET DEFAULT nextval('proof_id_seq'::regclass);


--
-- Name: rule id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule ALTER COLUMN id SET DEFAULT nextval('rule_id_seq'::regclass);


--
-- Name: step id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step ALTER COLUMN id SET DEFAULT nextval('step_id_seq'::regclass);


--
-- Name: subject id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject ALTER COLUMN id SET DEFAULT nextval('subject_id_seq'::regclass);


--
-- Name: translation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation ALTER COLUMN id SET DEFAULT nextval('translation_id_seq'::regclass);


--
-- Data for Name: definition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY definition (id, rule_id) FROM stdin;
1	1
2	2
3	3
4	4
5	5
6	6
7	7
8	11
9	16
10	18
11	20
12	22
13	23
14	24
\.


--
-- Name: definition_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('definition_id_seq', 14, true);


--
-- Data for Name: descriptor; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY descriptor (id) FROM stdin;
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
\.


--
-- Name: descriptor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('descriptor_id_seq', 22, true);


--
-- Data for Name: expression; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY expression (id, data, hash, latex, functions, node_type, node_value, node_arguments) FROM stdin;
1	\\x000000000100010009000000000000	\\x43015c596372b689f4f4cefecd30ec1668862206980cb58d65afb225d9c9cbe1	{}_\\text{?}a	{9}	generic	9	{}
2	\\x00000000010001000a000000000000	\\x7411a5ca9021c1572527e434ecfc5439b308a4c41d55e3ee2ce343cf960f5eb4	{}_\\text{?}b	{10}	generic	10	{}
3	\\x00000000020001000a00000007000000000001000100	\\xd419c9a79fedb89dd8fe433025dd1b7eae46f975b3982323e3eccea316b34423	-{}_\\text{?}b	{10,7}	function	7	{2}
4	\\x0000000004000200090000000a0000000200000007000000000000000200010002000301	\\x06c4317b0d80c1ce50664d8365b0cf06da41d15dbc6038d7f6c18952206908fc	{}_\\text{?}a+-{}_\\text{?}b	{9,10,2,7}	function	2	{1,3}
5	\\x0000000003000200090000000a00000003000000000000000200020001	\\x8af96fecdd3af832e9be5b6e7e23e27060e194b300e94a93954ac7e2dc1c2ee1	{}_\\text{?}a-{}_\\text{?}b	{9,10,3}	function	3	{1,2}
6	\\x0000000003000200090000000a00000004000000000000000200020001	\\xa21a2c2ab7610ca971fa03ef17af32bedb693c45c7877bcb7044ebe488983ee5	{}_\\text{?}a{}_\\text{?}b	{9,10,4}	function	4	{1,2}
7	\\x00000000010001000b000000000000	\\x81e70705060646c78a583ab14aabcd545598cbcd420c7973aba1675c2e8b705f	{}_\\text{?}c	{11}	generic	11	{}
8	\\x0000000003000200090000000b00000004000000000000000200020001	\\xb663acd854dc781f7c56f92ffc5a13a6ebb33ca51b0290a1933a94d5212c4639	{}_\\text{?}a{}_\\text{?}c	{9,11,4}	function	4	{1,7}
9	\\x0000000005000300090000000a0000000b00000002000000040000000000000000000200020003040001040002	\\xda3e94d9a6b49580ebd17ab5ea06b39f39587525854be82bfcfa859de1039c21	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}c	{9,10,11,2,4}	function	2	{6,8}
10	\\x00000000030002000a0000000b00000002000000000000000200020001	\\x77b5554abc9aee843fabdb8d710fc6601e1ba533ba6f40d2adc25573ffa87c1b	{}_\\text{?}b+{}_\\text{?}c	{10,11,2}	function	2	{2,7}
11	\\x0000000005000300090000000a0000000b0000000400000002000000000000000000020002000300040102	\\x0aa7057218958cccb8a12433b953a3057847686b280a2cd275d8a3302272f883	{}_\\text{?}a\\left({}_\\text{?}b+{}_\\text{?}c\\right)	{9,10,11,4,2}	function	4	{1,10}
12	\\x00000000020001000900000007000000000001000100	\\xed9dae5554a70accaa92a3285e84500169047310a233a67d2402da9763e44a08	-{}_\\text{?}a	{9,7}	function	7	{1}
13	\\x00000100000000000100000000	\\xcb8c6ede8e7aef082d6b7f80058cc9b51caf8daeea698e065be21383c51065fc	1	{}	integer	1	{}
14	\\x0000010001000000010000000700000001000001	\\x67c383bff6469fd3ef635e7f21fbec2e7a4fb5a5108bdbed69d982793074a848	-1	{7}	function	7	{13}
15	\\x00000100030001000100000009000000040000000700000000000200010001020300	\\x7868708f462030521b1f3b26b9818bac00b5429f492f4a5a295135be1c9c34f4	-1{}_\\text{?}a	{9,4,7}	function	4	{14,1}
16	\\x000001000200010001000000090000000600000000000200010002	\\x209140cc8cd71d6d036ba4d6b5f19ec77881b6105cfe09185569ee40cc8020c3	{}_\\text{?}a^{1}	{9,6}	function	6	{1,13}
17	\\x0000000003000200090000000a00000006000000000000000200020001	\\x179655ebc9a1bcc8e05debe8a5658f6c6f5a5a339934ca54eb5e2dc0df1ea618	{}_\\text{?}a^{{}_\\text{?}b}	{9,10,6}	function	6	{1,2}
18	\\x0000000003000200090000000b00000006000000000000000200020001	\\x1a68a647472dc53cf6fbab82825d05945bbc1b46a029514b05127173eb68c1d6	{}_\\text{?}a^{{}_\\text{?}c}	{9,11,6}	function	6	{1,7}
19	\\x0000000005000300090000000a0000000b00000004000000060000000000000000000200020003040001040002	\\xf737887c811816a54bb3ad9658d5ea4b07623762a32802bfbe85dbdd536a1618	{}_\\text{?}a^{{}_\\text{?}b}{}_\\text{?}a^{{}_\\text{?}c}	{9,10,11,4,6}	function	4	{17,18}
20	\\x0000000005000300090000000a0000000b0000000600000002000000000000000000020002000300040102	\\x0846ec457cce9d4c9ed47441fbff1e93670ad5b8f20e649e86579904ddfe839e	{}_\\text{?}a^{{}_\\text{?}b+{}_\\text{?}c}	{9,10,11,6,2}	function	6	{1,10}
21	\\x000000000100010014000000000000	\\xa87b85903b7498010c55645a4a6c27c9309925173a6177bdcb37e9f6e4354ef2	{}_\\text{?}x	{20}	generic	20	{}
22	\\x00000000020002001600000014000000010000000001	\\xf7ad21a772c67ff2678b7e83ba90a5b962cc5487adbba18b082688cc387d7ffe	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{22,20}	generic	22	{21}
23	\\x000000000300020014000000160000001900000000000100020002000100	\\x3f8ac895dfad545ad6ad91a2ed1c8d0c22a1a238ef3e03997e043406734b1df1	\\frac{\\partial}{\\partial{}_\\text{?}x}{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{20,22,25}	function	25	{21,22}
24	\\x00000000020001001400000017000000000001000100	\\x60e62d80304fa9ac770f84c9df8a04815c066b13420feb521878eba6e59b7eda	\\Delta{}_\\text{?}x	{20,23}	function	23	{21}
25	\\x00000100000000000000000000	\\xe0afadbd718beefc7b9ec03c368f7f78a9eae4327d59216840678ede42d2fd96	0	{}	integer	0	{}
26	\\x000000000300010014000000020000001700000000000200010001000200	\\xac989ff477bf681528e055ae65e795bca03aa152aa0206bf442cf589a7ac024a	{}_\\text{?}x+\\Delta{}_\\text{?}x	{20,2,23}	function	2	{21,24}
27	\\x00000000040002001600000014000000020000001700000001000000020001000002010301	\\xfadd710643637b7e3c9172b884784111c44b611f1fc2be9bad580c1477ff9666	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}	{22,20,2,23}	generic	22	{26}
28	\\x00000000050002001600000014000000030000000200000017000000010000000200020001000200030104010001	\\xc02fcd98f76ef3854b6c11f1ad0369f6704de620e3a2236e6655d1bf30d13124	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{22,20,3,2,23}	function	3	{27,22}
29	\\x00000000060002001600000014000000050000000300000002000000170000000100000002000200020001000203000401050100010501	\\x9a705a3331eec10cdd8b82a01f7833b787395e50064fea1ed1f64c6ad9b122b9	\\frac{~{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}~}{~\\Delta{}_\\text{?}x~}	{22,20,5,3,2,23}	function	5	{28,24}
30	\\x000001000700020000000000140000001600000018000000170000000500000003000000020000000000010003000100020002000200020300070405010600030001000300	\\x0c0208b22a214904a0a0c2ded23fba5a80dec90381e229f3d98a6b03c898df4d	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}~}{~\\Delta{}_\\text{?}x~}	{20,22,24,23,5,3,2}	function	24	{24,25,29}
31	\\x0000000003000200090000000a00000002000000000000000200020001	\\xbbc12982203caf5c28570b4b7572807cb104402f42592fbf8e89f78b515dc6be	{}_\\text{?}a+{}_\\text{?}b	{9,10,2}	function	2	{1,2}
32	\\x0000000005000300090000000a0000000b0000000100000002000000000000000000020002000304000102	\\x3016de2afffb248f1ea49db18fd6195b302570e3ae88e30f8b76342c10805094	{}_\\text{?}a+{}_\\text{?}b={}_\\text{?}c	{9,10,11,1,2}	function	1	{31,7}
33	\\x00000000030002000b0000000a00000003000000000000000200020001	\\x23285930815435e505a21977f2f204227e504baca69f65c92a12c89fffdbe338	{}_\\text{?}c-{}_\\text{?}b	{11,10,3}	function	3	{7,2}
34	\\x0000000005000300090000000b0000000a0000000100000003000000000000000000020002000300040102	\\xd069cd39c47b53d1aafbf0166e90bf5b6e00b9450a793b22eed278f3525fac3c	{}_\\text{?}a={}_\\text{?}c-{}_\\text{?}b	{9,11,10,1,3}	function	1	{1,33}
35	\\x0000000002000100090000000400000000000200010000	\\x0ae10431daf1fbea1a3744536130d7e98fa9347dcff9278b3d463aa92a355e99	{}_\\text{?}a{}_\\text{?}a	{9,4}	function	4	{1,1}
36	\\x0000010003000100010000000900000004000000060000000000020002000100020003	\\x4ec5cfd089fbb50f6e2cac611494fba37d8c929dcdefff42605895513b9e52d3	{}_\\text{?}a{}_\\text{?}a^{1}	{9,4,6}	function	4	{1,16}
37	\\x00000100030001000100000009000000040000000600000000000200020001020003020003	\\xb4a8ec20c55c1f0bdd7564854c0b84b5400c82a7cc067b2a65dd84f7c3b7bc1c	{}_\\text{?}a^{1}{}_\\text{?}a^{1}	{9,4,6}	function	4	{16,16}
38	\\x00000100000000000200000000	\\xe62115b1b0a0940392fe419abadbc906d524d2f5e005ce2c982949ac518fc3d2	2	{}	integer	2	{}
39	\\x000001000200010002000000090000000600000000000200010002	\\x4d211308d49e14146f22cea3417f83f8fca62aa4a86d2aeb420427cfb73a1a76	{}_\\text{?}a^{2}	{9,6}	function	6	{1,38}
40	\\x00000000030002000a0000000900000002000000000000000200020001	\\x1c0822992da41678b0205742c498897c9eba47acc1d317bd1c36c3b7ecbaa54d	{}_\\text{?}b+{}_\\text{?}a	{10,9,2}	function	2	{2,1}
41	\\x00000000050003000a000000090000000b0000000100000002000000000000000000020002000304000102	\\x2a6e5af7d3b037582af6a5d0500341f4691156fa1d845f271665bde426bd57ff	{}_\\text{?}b+{}_\\text{?}a={}_\\text{?}c	{10,9,11,1,2}	function	1	{40,7}
42	\\x00000000030002000b0000000900000003000000000000000200020001	\\xb841f29e36d50117eb657ad10b5213b3d9ebcf9899a134a0c79660d15179bd0c	{}_\\text{?}c-{}_\\text{?}a	{11,9,3}	function	3	{7,1}
43	\\x00000000050003000a0000000b000000090000000100000003000000000000000000020002000300040102	\\x42654eee6a95a16987fd329b3a26f3b6b65762fb0f5be2e5fbf41014e676ee63	{}_\\text{?}b={}_\\text{?}c-{}_\\text{?}a	{10,11,9,1,3}	function	1	{2,42}
44	\\x00000000030002000a0000000900000004000000000000000200020001	\\x5ab22a4e6f77880af3916b063e9d5e84e4b5506e2743a9998d8d966a3211f487	{}_\\text{?}b{}_\\text{?}a	{10,9,4}	function	4	{2,1}
45	\\x00000000030002000b0000000900000004000000000000000200020001	\\xc9f19246a00f2ff5de24694aa5fe9bceece277c795866b24871992c5bf0fd9aa	{}_\\text{?}c{}_\\text{?}a	{11,9,4}	function	4	{7,1}
46	\\x00000000050003000a000000090000000b00000002000000040000000000000000000200020003040001040201	\\x0b483f5d5c667875d4a5c63591958b7af91d144572fcb8d98e07cfbb8a267691	{}_\\text{?}b{}_\\text{?}a+{}_\\text{?}c{}_\\text{?}a	{10,9,11,2,4}	function	2	{44,45}
47	\\x00000000050003000a000000090000000b00000002000000040000000000000000000200020003040001040102	\\x83083f81df6fae38a050ff7e725fcceb6443c40c4b1102c190458e27a73cb40b	{}_\\text{?}b{}_\\text{?}a+{}_\\text{?}a{}_\\text{?}c	{10,9,11,2,4}	function	2	{44,8}
48	\\x000001000200010001000000090000000400000000000200010200	\\xf69e3da77bef6544638d46b6830955372b6998c4df20f1c75737895df6774b60	1{}_\\text{?}a	{9,4}	function	4	{13,1}
49	\\x00000000050003000a0000000b000000090000000400000002000000000000000000020002000304000102	\\x8258c3049688cb400172c5f296bf389d67a5868dc85df11832df355dc9bb23fe	\\left({}_\\text{?}b+{}_\\text{?}c\\right){}_\\text{?}a	{10,11,9,4,2}	function	4	{10,1}
50	\\x0000000002000100090000000200000000000200010000	\\xea3524b07551e5b7330386455760cfe4902f4af00ebd3cf58c59673edd54e569	{}_\\text{?}a+{}_\\text{?}a	{9,2}	function	2	{1,1}
51	\\x0000010003000100010000000900000002000000040000000000020002000100020300	\\xf5a4ccbc4969c20336995c79f3004bd1b0b7eabd6747cbc509695feca3b20bbb	{}_\\text{?}a+1{}_\\text{?}a	{9,2,4}	function	2	{1,48}
52	\\x00000100030001000100000009000000020000000400000000000200020001020300020300	\\xfe23c1b9a154d031192853453aa034ac20fb167f37f276fbfda17dd4c40e634c	1{}_\\text{?}a+1{}_\\text{?}a	{9,2,4}	function	2	{48,48}
53	\\x000001000200010002000000090000000400000000000200010200	\\xc483d6efc03b7e59e8eda204304b6737b0369bf0bc046e8da7653e461f0fca5d	2{}_\\text{?}a	{9,4}	function	4	{38,1}
54	\\x000001000400020002000000090000000a000000060000000200000000000000020002000203000104	\\xd313f6f7ee11b69056ae1c1d658fa344fdbbc21214cb809f5fc385adcffcba9f	\\left({}_\\text{?}a+{}_\\text{?}b\\right)^{2}	{9,10,6,2}	function	6	{31,38}
55	\\x0000000004000200090000000a0000000400000002000000000000000200020002030001030001	\\x2074eb1268de9b79d2324bba90da55d8c90777241361e3af6266264c521ad697	\\left({}_\\text{?}a+{}_\\text{?}b\\right)\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{9,10,4,2}	function	4	{31,31}
56	\\x0000000004000200090000000a000000040000000200000000000000020002000200030001	\\xa4ea8baad251ef6ddd790d3a0dc0784eec70d0ea6eb2d1d0240e0c6f88c649db	{}_\\text{?}a\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{9,10,4,2}	function	4	{1,31}
57	\\x00000000040002000a00000009000000040000000200000000000000020002000200030100	\\xcd170f1ab702d2b70754953773b17866c7ea24331a73fe6c6f5c6fc278f7ecd1	{}_\\text{?}b\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{10,9,4,2}	function	4	{2,31}
58	\\x0000000004000200090000000a000000020000000400000000000000020002000203000200010301020001	\\x8afbfe93a9bceaa76915a83dc8ef9ad7b2b40a32383b1cce59e03fcc6cf4d939	{}_\\text{?}a\\left({}_\\text{?}a+{}_\\text{?}b\\right)+{}_\\text{?}b\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{56,57}
59	\\x00000000020001000a0000000400000000000200010000	\\x2a8af03c97229e276d4d5fa76a171cc377aa5b2acdd63f8d7c6a8f38d2f529fe	{}_\\text{?}b{}_\\text{?}b	{10,4}	function	4	{2,2}
60	\\x00000000040002000a000000090000000200000004000000000000000200020002030001030000	\\x06ee2312065ec06e667b3dffda8e9e27841ccea26e620dea82c87367a749c204	{}_\\text{?}b{}_\\text{?}a+{}_\\text{?}b{}_\\text{?}b	{10,9,2,4}	function	2	{44,59}
61	\\x0000000004000200090000000a0000000200000004000000000000000200020002030002000102030100030101	\\xae4bff0f3f4385e10f5aa78618091c28bbfa3468d03949021ea63bfed9d18c54	{}_\\text{?}a\\left({}_\\text{?}a+{}_\\text{?}b\\right)+\\left({}_\\text{?}b{}_\\text{?}a+{}_\\text{?}b{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{56,60}
62	\\x0000000004000200090000000a0000000200000004000000000000000200020002030000030001	\\x71cbe01cc8f7d354ae6f879a6cbf0c90fc2842d1327fa126ef2d8d959fe3e86f	{}_\\text{?}a{}_\\text{?}a+{}_\\text{?}a{}_\\text{?}b	{9,10,2,4}	function	2	{35,6}
63	\\x0000000004000200090000000a00000002000000040000000000000002000200020203000003000102030100030101	\\xe271693f9533856f25ed61e14e3f0779c42cd68ba685bea9b6848b59e3fa91b6	{}_\\text{?}a{}_\\text{?}a+{}_\\text{?}a{}_\\text{?}b+\\left({}_\\text{?}b{}_\\text{?}a+{}_\\text{?}b{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{62,60}
64	\\x0000000004000200090000000a0000000200000004000000000000000200020002030001030100	\\xea1bb62f8fb69468b41fb4fc810d81ae4b604531e1b6bf1840fdc0957613a040	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b{}_\\text{?}a	{9,10,2,4}	function	2	{6,44}
65	\\x0000000004000200090000000a000000020000000400000000000000020002000203000002030001030100	\\xe816ece46b40654c8ad0a9153a234029da963d1e5db29e5c08b2550842cd4bdf	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b{}_\\text{?}a\\right)	{9,10,2,4}	function	2	{35,64}
66	\\x0000000004000200090000000a00000002000000040000000000000002000200020203000002030001030100030101	\\xb046ec346346771815b2e8efb9c049a0e3872b315b989e4b0a7d82c37a6fef54	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b{}_\\text{?}a\\right)+{}_\\text{?}b{}_\\text{?}b	{9,10,2,4}	function	2	{65,59}
67	\\x0000000004000200090000000a0000000200000004000000000000000200020002030001030001	\\xfd3e76a6a346e596e5aa8cdf9a293cf0b92d806893e5b63f471d323855707d6e	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b	{9,10,2,4}	function	2	{6,6}
68	\\x0000000004000200090000000a000000020000000400000000000000020002000203000002030001030001	\\xab02f94d23d66ec33060af3985e4fc57963e0d003f93ad23a7ce6a851b98455f	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{35,67}
69	\\x0000000004000200090000000a00000002000000040000000000000002000200020203000002030001030001030101	\\x151ee194319544fce3a02a9e93f0b42b5823093bae446153cbb79e48727b9aa8	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b{}_\\text{?}b	{9,10,2,4}	function	2	{68,59}
70	\\x0000010002000100020000000a0000000600000000000200010002	\\x7e4376c3449ddfadfd4229cd1954411a1b59a1a8d74e30c993b857bf1c8cc6a8	{}_\\text{?}b^{2}	{10,6}	function	6	{2,38}
71	\\x000001000500020002000000090000000a00000002000000040000000600000000000000020002000200020203000002030001030001040105	\\x40eedbba961b2989927596839dfdbdcf01aa17a5305c6159c7373177f129f06b	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b^{2}	{9,10,2,4,6}	function	2	{68,70}
72	\\x000001000300020002000000090000000a000000040000000000000002000203020001	\\x061437dcbcd38a8878bb7ca3ce6eb5c21cbbf11def26ade399e7908464b6cf2f	2\\left({}_\\text{?}a{}_\\text{?}b\\right)	{9,10,4}	function	4	{38,6}
73	\\x000001000400020002000000090000000a00000002000000040000000000000002000200020300000304030001	\\xd117a3ccc4e14bc31191ea4540552440278b55431ba11a78e5c2d2c37b00218a	{}_\\text{?}a{}_\\text{?}a+2\\left({}_\\text{?}a{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{35,72}
74	\\x000001000500020002000000090000000a0000000200000004000000060000000000000002000200020002020300000305030001040105	\\xf11e3a258819b2882bbb3b9b0d6793e1c9719a9a9bf8d51d545abd3089677394	{}_\\text{?}a{}_\\text{?}a+2\\left({}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b^{2}	{9,10,2,4,6}	function	2	{73,70}
75	\\x000001000500020002000000090000000a00000002000000060000000400000000000000020002000200020300050405040001	\\xd885d6e7c27ea77f527713a27b361f1ce1644399f3df4d839d1c4b406618754a	{}_\\text{?}a^{2}+2\\left({}_\\text{?}a{}_\\text{?}b\\right)	{9,10,2,6,4}	function	2	{39,72}
76	\\x000001000500020002000000090000000a0000000200000006000000040000000000000002000200020002020300050405040001030105	\\x677d41e596887be58bc74465aa0f8de4d6b33473c86b854f52b190273e3bb39e	{}_\\text{?}a^{2}+2\\left({}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b^{2}	{9,10,2,6,4}	function	2	{75,70}
77	\\x000001000300020002000000090000000a000000040000000000000002000202030001	\\x16a2aa9ed030f0cffd910d289ea46fa10475798b7b2a7cdd7a1a7cf9abf2a959	2{}_\\text{?}a{}_\\text{?}b	{9,10,4}	function	4	{53,2}
78	\\x000001000500020002000000090000000a00000002000000060000000400000000000000020002000200020300050404050001	\\x343c15e0a2fa90b24abf2c531d6ed512d6684b7a8ac30c268004180c82b23e6b	{}_\\text{?}a^{2}+2{}_\\text{?}a{}_\\text{?}b	{9,10,2,6,4}	function	2	{39,77}
79	\\x000001000500020002000000090000000a0000000200000006000000040000000000000002000200020002020300050404050001030105	\\xe86dabb335751acfd48c86437475e903d1924d8a26b32c525792e706a1a7f7a5	{}_\\text{?}a^{2}+2{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b^{2}	{9,10,2,6,4}	function	2	{78,70}
80	\\x000001000200010000000000090000000400000000000200010200	\\x77ca76e6b8c82d47b148ca0b4ada2224dce12fec41fa2a4e2b1b2da36a4fd5a1	0{}_\\text{?}a	{9,4}	function	4	{25,1}
81	\\x0000000002000100090000000300000000000200010000	\\xb07f2e67b317e0a7480efcc06791dd124780b23f8d64510676e4d2d1bea3b5cc	{}_\\text{?}a-{}_\\text{?}a	{9,3}	function	3	{1,1}
82	\\x000000000300010009000000020000000700000000000200010001000200	\\x6dbf3c8a1aeeb0bc0579c53b92ddafb8fbd7ac26a0a5a0ac74f0d64aa40f1a4e	{}_\\text{?}a+-{}_\\text{?}a	{9,2,7}	function	2	{1,12}
83	\\x0000010000000000ffffffff00	\\xa9015325dd84a5fe32a973b297d83926289efe354948451371a303d3ee305184	-1	{}	integer	-1	{}
84	\\x0000010002000100ffffffff090000000400000000000200010200	\\x053d4fae4c8a0b210c534d9743d824995f79795e073a0adeca8c3c59a126092e	-1{}_\\text{?}a	{9,4}	function	4	{83,1}
85	\\x0000010003000100ffffffff0900000002000000040000000000020002000100020300	\\xaa5abe7aaea2e725fea5a476562ff984766fd24dda32297eee92ef85602d0935	{}_\\text{?}a+-1{}_\\text{?}a	{9,2,4}	function	2	{1,84}
86	\\x000002000300010001000000ffffffff09000000020000000400000000000200020001020300020400	\\x3099c740ea0b4396ffa11c0cf5c6bafa9e81bf028192446cebbe95515ca12167	1{}_\\text{?}a+-1{}_\\text{?}a	{9,2,4}	function	2	{48,84}
87	\\x000001000200010000000000090000000200000000000200010002	\\x182374522020321381c4df9d629cb67f7166efb02e48e6810ca7539aedecb71b	{}_\\text{?}a+0	{9,2}	function	2	{1,25}
88	\\x000001000200010000000000090000000200000000000200010200	\\xc1643dedd639c96950f9dc40955b094ee6f7c686847444dbdb5b168e60218586	0+{}_\\text{?}a	{9,2}	function	2	{25,1}
89	\\x0000000004000200090000000a000000050000000400000000000000020002000203000101	\\xa2c62db2f2d6d6f67dc6c08ae19fd72390fe58dbf84c858ec45deadc5e8953b2	\\frac{~{}_\\text{?}a{}_\\text{?}b~}{~{}_\\text{?}b~}	{9,10,5,4}	function	5	{6,2}
90	\\x00000000040002000a00000009000000050000000400000000000000020002000203000100	\\xb9e626c400d02409898b614499a4dfa4e8b7e3622d85a81476959832767c249b	\\frac{~{}_\\text{?}b{}_\\text{?}a~}{~{}_\\text{?}b~}	{10,9,5,4}	function	5	{44,2}
91	\\x000000000100010015000000000000	\\x90f5e58b9c74fdbc76e008c0f556e88fca176f2c9f8f53474e1edb69caa15cda	{}_\\text{?}y	{21}	generic	21	{}
92	\\x0000000003000200140000001500000002000000000000000200020001	\\xd50ef21beb2ab7f1df2ec2c64c83e36c71b4731cd99ae2feef1c0c1607b47ff5	{}_\\text{?}x+{}_\\text{?}y	{20,21,2}	function	2	{21,91}
93	\\x0000000006000400090000000a00000014000000150000001800000002000000000000000000000003000200040001050203	\\xad31e54dab7cc0ff194c49220bb39573b718e9807813677b16dca85a2ddc9ff6	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}x+{}_\\text{?}y	{9,10,20,21,24,2}	function	24	{1,2,92}
94	\\x0000000004000300090000000a0000001400000018000000000000000000030003000102	\\xa2d6fedb431cda508340d8a47b38cf8a91ad854264eb25d1e8cc9ef3a0b10b20	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}x	{9,10,20,24}	function	24	{1,2,21}
95	\\x0000000004000300090000000a0000001500000018000000000000000000030003000102	\\x538389d041f9a918fc7097615b3c56bb12398a35e05767ad96ae50d10c3c2818	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}y	{9,10,21,24}	function	24	{1,2,91}
96	\\x0000000006000400090000000a00000014000000150000000200000018000000000000000000000002000300040500010205000103	\\x14e403d209228f4b9f9d60ed0b0ae8172be49c94b3eae2bef413f27d94457b89	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}x+\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}y	{9,10,20,21,2,24}	function	2	{94,95}
97	\\x00000100020001000000000009000000180000000000030001000200	\\x831542a9312e8ad531d8961f240ae37d1c11d946abea2abf2552688a9549fe9a	\\lim_{{}_\\text{?}a\\to0}{}_\\text{?}a	{9,24}	function	24	{1,25,1}
98	\\x0000000004000300090000000a0000000b00000018000000000000000000030003000102	\\x3e53d1602910c3f6bdb4d33a5654feec2993e915ddc23033e8eab0ce184683f1	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}c	{9,10,11,24}	function	24	{1,2,7}
99	\\x000001000200010002000000140000000600000000000200010002	\\x62f9298814fbef0f07ab742113e462589c79abee85888c323acf0ee16c3c835b	{}_\\text{?}x^{2}	{20,6}	function	6	{21,38}
100	\\x0000010003000100020000001400000019000000060000000000020002000100020003	\\x5261ca0a13eaec8fd19130ccc719ca3bb58fb7763dcb174219b5405d33ef2a4c	\\frac{\\partial}{\\partial{}_\\text{?}x}{}_\\text{?}x^{2}	{20,25,6}	function	25	{21,99}
101	\\x000001000400010002000000140000000600000002000000170000000000020002000100010200030004	\\x9bd492f217b15d49887878b8e8ae6655d74c48fcc20bd333bf5db78a6dcffe99	\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}	{20,6,2,23}	function	6	{26,38}
102	\\x00000100050001000200000014000000030000000600000002000000170000000000020002000200010001020300040005020005	\\x7ff40cbef836b450e7d7dd14710db2d3c9077b9e968d47d64f83ccdc799e6d21	\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}-{}_\\text{?}x^{2}	{20,3,6,2,23}	function	3	{101,99}
103	\\x00000100060001000200000014000000050000000300000006000000020000001700000000000200020002000200010001020304000500060300060500	\\xc7bdbafa893b8ac67e6deefffb5458f9466e973f00fb2894906711f4abad9f16	\\frac{~\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,5,3,6,2,23}	function	5	{102,24}
104	\\x000002000700010000000000020000001400000018000000170000000500000003000000060000000200000000000300010002000200020002000102000703040506000200080500080200	\\x351ceb2ad9c51cd8e45cd2720ec583fbb024088926f31f4c1869c1f25e770974	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,3,6,2}	function	24	{24,25,103}
105	\\x000001000200010002000000140000000400000000000200010200	\\x09d3bdc3f0c9c1619427642cd6e36261bde78ddbc183e3b4cd6bcfd4cc7775a6	2{}_\\text{?}x	{20,4}	function	4	{38,21}
106	\\x000001000300010002000000140000000400000017000000000002000100010103000200	\\xa3997211da42cd177c865dee749ed753152b2706c7bbffe4cd0cdcb565b9dd15	2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,4,23}	function	4	{105,24}
107	\\x00000100050001000200000014000000020000000600000004000000170000000000020002000200010001020005030305000400	\\x087aee94a74e8d96c216dd7de20192e0a2dffbb88a0657a83e603437d21a1e5f	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,6,4,23}	function	2	{99,106}
108	\\x00000100030001000200000014000000060000001700000000000200010001020003	\\x99ea7d6d5b9b5b91993ca47a142a9c6de63f98a3c70b75e96af8d806ab56924a	\\Delta{}_\\text{?}x^{2}	{20,6,23}	function	6	{24,38}
109	\\x000001000500010002000000140000000200000006000000040000001700000000000200020002000100010102000503030500040002040005	\\xca8cc9e7abbce3578344c75b29e0e821f2131de81a3378625fb015f7dba765ef	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}	{20,2,6,4,23}	function	2	{107,108}
110	\\x00000100060001000200000014000000030000000200000006000000040000001700000000000200020002000200010001020203000604040600050003050006030006	\\x2cac67207636a99b319b26136644dcada790debb3af306e3a83c4a03fb786e49	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}-{}_\\text{?}x^{2}	{20,3,2,6,4,23}	function	3	{109,99}
111	\\x00000100070001000200000014000000050000000300000002000000060000000400000017000000000002000200020002000200010001020303040007050507000600040600070400070600	\\x467eff6acd76043c81fd91e933923fc0b2ce17295447493ef2878d414be9c8b8	\\frac{~{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,5,3,2,6,4,23}	function	5	{110,24}
112	\\x000002000800010000000000020000001400000018000000170000000500000003000000020000000600000004000000000003000100020002000200020002000102000803040505060009070709000200060200090600090200	\\xa1b4275852b515902638977fa8eab85188859d38d785cfbfc86964e1b00b923f	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,3,2,6,4}	function	24	{24,25,111}
113	\\x00000100030001000200000014000000070000000600000000000100020001020003	\\xa1b35aff4c69d746b7f4d179343502063bf46aefa47825fc70e6918cbef3d54f	-\\left({}_\\text{?}x^{2}\\right)	{20,7,6}	function	7	{99}
114	\\x0000010006000100020000001400000002000000060000000400000017000000070000000000020002000200010001000101010200060303060004000204000605020006	\\xa1f74f529a1e22a5962f6475e8bc4854d6fd2af0948edd956ad9acec996c8065	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)	{20,2,6,4,23,7}	function	2	{109,113}
115	\\x0000010007000100020000001400000005000000020000000600000004000000170000000700000000000200020002000200010001000102020203000704040700050003050007060300070500	\\x6104aa62571c6822dc97921130a8be5cf27da818a728bcc45fbb4b791697f15d	\\frac{~{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)~}{~\\Delta{}_\\text{?}x~}	{20,5,2,6,4,23,7}	function	5	{114,24}
116	\\x00000200080001000000000002000000140000001800000017000000050000000200000006000000040000000700000000000300010002000200020002000100010200080304040405000906060900020005020009070500090200	\\x1e7c2fa4e08c3284455b6e268e202b32a8a5872c2021ff4925ed05919186a06d	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,6,4,7}	function	24	{24,25,115}
117	\\x0000010004000100020000001400000002000000060000000700000000000200020001000102000403020004	\\xcbfbc1051d034874f6e3ee2352f5ad571fc02c95142fb24e1e8d9bfe81df9ede	{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)	{20,2,6,7}	function	2	{99,113}
118	\\x000001000600010002000000140000000200000006000000070000000400000017000000000002000200010002000100010102000603020006040406000500	\\x87e68f1e2bcebd9796ebebe245e5fa21f0f09638156f32a2b200567a4593bb01	{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,6,7,4,23}	function	2	{117,106}
119	\\x0000010006000100020000001400000002000000060000000700000004000000170000000000020002000100020001000101010200060302000604040600050002050006	\\xf6019e8d28022c3ce6fc4bae02a298e11853509e096066e4244a7f667d908e5f	{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}	{20,2,6,7,4,23}	function	2	{118,108}
120	\\x0000010007000100020000001400000005000000020000000600000007000000040000001700000000000200020002000100020001000102020203000704030007050507000600030600070600	\\x8028254686c803b193720e11d8df854e197e872ecb92974d9bdd6b7a974e45a7	\\frac{~{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,5,2,6,7,4,23}	function	5	{119,24}
121	\\x00000200080001000000000002000000140000001800000017000000050000000200000006000000070000000400000000000300010002000200020001000200010200080304040405000906050009070709000200050200090200	\\xb8b8980b868afa0d3052e190f235fb4ea77ec9413ae8499ef6a8d56e3448bd99	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,6,7,4}	function	24	{24,25,120}
122	\\x00000000030001001400000004000000170000000000020001000102000200	\\x56804013f2b251de4d803b3f097ae2d7e58e21a50746925bbabd1fbafcbc2ec2	\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,4,23}	function	4	{24,24}
123	\\x000001000600010002000000140000000200000006000000070000000400000017000000000002000200010002000100010101020006030200060404060005000405000500	\\x0c5a5199aacaeaefa352aedca8cc55c82851cf2dd7bd3dc9187d7fb856994580	{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,6,7,4,23}	function	2	{118,122}
124	\\x000001000700010002000000140000000500000002000000060000000700000004000000170000000000020002000200010002000100010202020300070403000705050700060005060006000600	\\x662e33f7e420e86971f6081503d956e09987a2722c0e537eb3b47dd05df4cdcf	\\frac{~{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,6,7,4,23}	function	5	{123,24}
125	\\x0000020008000100000000000200000014000000180000001700000005000000020000000600000007000000040000000000030001000200020002000100020001020008030404040500090605000907070900020007020002000200	\\xeb89ac23669f8087b97622f305d95d6f7796d0147f198a24640b45f98841a4a3	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}+-\\left({}_\\text{?}x^{2}\\right)+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,6,7,4}	function	24	{24,25,124}
126	\\x00000100030001000200000014000000030000000600000000000200020001020003020003	\\x7951756a07cb0f2580d1f286ca9ef9e279fb4615d82b3b65756dc83a941ddd3a	{}_\\text{?}x^{2}-{}_\\text{?}x^{2}	{20,3,6}	function	3	{99,99}
127	\\x0000010006000100020000001400000002000000030000000600000004000000170000000000020002000200020001000102030006030006040406000500	\\xc67dd806e469dbade6c9e9aca1eb9f9f9da5ffaab37f5ac16d278671bd11cd73	{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,3,6,4,23}	function	2	{126,106}
128	\\x0000010006000100020000001400000002000000030000000600000004000000170000000000020002000200020001000101020300060300060404060005000405000500	\\x44449858767c42dbd6f161dda26698c9d90fff4a303e11347fecb69aa175ec24	{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,3,6,4,23}	function	2	{127,122}
129	\\x0000010007000100020000001400000005000000020000000300000006000000040000001700000000000200020002000200020001000102020304000704000705050700060005060006000600	\\x45936a973cf51349bb8bf87c11a1c7389d6eea748a9f07386a0b49f9a35661d1	\\frac{~{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,3,6,4,23}	function	5	{128,24}
130	\\x00000200080001000000000002000000140000001800000017000000050000000200000003000000060000000400000000000300010002000200020002000200010200080304040506000906000907070900020007020002000200	\\xce3d479939f05e03595746bfe35dc3c8d336e1d63101c3a01c13bcc659d779ca	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,3,6,4}	function	24	{24,25,129}
131	\\x000002000400010000000000020000001400000002000000040000001700000000000200020001000104020205000300	\\x9bc5569247c9f95b81ef25e4ce4b533940c056ff2ecbde14d95bf5da611aed88	0+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{25,106}
132	\\x000002000400010000000000020000001400000002000000040000001700000000000200020001000101040202050003000203000300	\\xf85d35fbd3b59ff39b8bb086d04a41e9eb06c01386ed676d1a261acc55d8533a	0+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{131,122}
133	\\x000002000500010000000000020000001400000005000000020000000400000017000000000002000200020001000102020503030600040003040004000400	\\x86c4b9c99e163ccdf5750ca13b0b538746b4d61ccc25dcc94ef19ee02c8e18bd	\\frac{~0+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,4,23}	function	5	{132,24}
134	\\x00000200060001000000000002000000140000001800000017000000050000000200000004000000000003000100020002000200010200060304040605050700020005020002000200	\\xa5a6ef549d77a84c0aa9c6c2dc1cfa4e9952175e7a0453e8336abbd25f27db55	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~0+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,4}	function	24	{24,25,133}
135	\\x000001000400010002000000140000000200000004000000170000000000020002000100010202040003000203000300	\\x7638e064865e8dc2b19098e3b68f8539c09a7630ade80975bfc10d4951785c38	2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{106,122}
136	\\x000001000500010002000000140000000500000002000000040000001700000000000200020002000100010203030500040003040004000400	\\x5cfea19f3d819017eba3b28ebe9d56394bfeffc4aa70b991588b3110d264ece7	\\frac{~2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,4,23}	function	5	{135,24}
137	\\x0000020006000100000000000200000014000000180000001700000005000000020000000400000000000300010002000200020001020006030405050700020005020002000200	\\x97f975f39048799a512d0605cc3c7393dcf9c8fb192519edb0994b6609bdcd1b	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,4}	function	24	{24,25,136}
138	\\x000001000400010002000000140000000200000004000000170000000000020002000100010204000300	\\x2774ff4e892ea728d6a1cd93a023b4234d3ad692479d06a9adb95d53429eff41	2{}_\\text{?}x+\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{105,24}
139	\\x000001000400010002000000140000000400000017000000020000000000020001000200010200030104000200	\\xdaf09486a3f940cbe1e6d57230e50f6b7b140e185b202ba457544dda4052fd53	\\Delta{}_\\text{?}x\\left(2{}_\\text{?}x+\\Delta{}_\\text{?}x\\right)	{20,4,23,2}	function	4	{24,138}
140	\\x000001000500010002000000140000000500000004000000170000000200000000000200020001000200010203000402050003000300	\\x6cea61c480b4db312f1a8deba0deea106ea75d6d214852294ebdacaf3001d5c4	\\frac{~\\Delta{}_\\text{?}x\\left(2{}_\\text{?}x+\\Delta{}_\\text{?}x\\right)~}{~\\Delta{}_\\text{?}x~}	{20,5,4,23,2}	function	5	{139,24}
141	\\x0000020006000100000000000200000014000000180000001700000005000000040000000200000000000300010002000200020001020006030402000504070002000200	\\xd1b239b6194646971c0fb492b728b1653f74e5be09babc6ccd47f012dc89d234	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~\\Delta{}_\\text{?}x\\left(2{}_\\text{?}x+\\Delta{}_\\text{?}x\\right)~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,4,2}	function	24	{24,25,140}
142	\\x0000020005000100000000000200000014000000180000001700000002000000040000000000030001000200020001020005030406000200	\\xde4b50707672a9a9b88dbe1996e52c023acc498a4d51d176e7b2cbbbbf60b26e	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x+\\Delta{}_\\text{?}x	{20,24,23,2,4}	function	24	{24,25,138}
143	\\x0000020004000100000000000200000014000000180000001700000004000000000003000100020001020004030500	\\x8f608aa1da0c1d683be164402dbd3862f781d95d5fb27e8ba0d9444a2e6d81c8	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x	{20,24,23,4}	function	24	{24,25,105}
144	\\x000001000300010000000000140000001800000017000000000003000100010200030200	\\xfeb0863162059a594fe4a202fc28ff687abba4a4defa28dbdcf70626064ea62a	\\lim_{\\Delta{}_\\text{?}x\\to0}\\Delta{}_\\text{?}x	{20,24,23}	function	24	{24,25,24}
145	\\x000002000500010000000000020000001400000002000000180000001700000004000000000002000300010002000102030005040600020300050300	\\xf7f5723c790985d130f6e5dc254e8fa33a2937d3c33ebee065b54d32e272f101	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x+\\lim_{\\Delta{}_\\text{?}x\\to0}\\Delta{}_\\text{?}x	{20,2,24,23,4}	function	2	{143,144}
146	\\x00000200050001000000000002000000140000000200000018000000170000000400000000000200030001000200010203000504060005	\\x58ab06ef9d441a1147a9530ba33b977657efa151e11e0fd46e7647a7f945ff21	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x+0	{20,2,24,23,4}	function	2	{143,25}
147	\\x000002000300010002000000000000001400000002000000040000000000020002000102030004	\\xbefa230147674ec5c7ecfb400702319f358515ba3828fcde33e502678c2076ae	2{}_\\text{?}x+0	{20,2,4}	function	2	{105,25}
\.


--
-- Name: expression_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('expression_id_seq', 147, true);


--
-- Data for Name: function; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY function (id, subject_id, descriptor_id, generic, rearrangeable, argument_count, keyword, keyword_type, latex_template) FROM stdin;
1	1	6	f	f	2	\N	\N	$0=$1
2	1	7	f	t	2	\N	\N	$0+$1
3	1	8	f	f	2	\N	\N	$0-$1
4	1	9	f	t	2	\N	\N	$0$1
5	1	10	f	f	2	frac	latex	\\frac{~$0~}{~$1~}
6	1	11	f	f	2	\N	\N	$0^{$1}
7	1	12	f	f	1	\N	\N	-$0
8	2	13	f	f	1	\N	\N	$0!
9	1	\N	t	f	0	a	symbol	\N
10	1	\N	t	f	0	b	symbol	\N
11	1	\N	t	f	0	c	symbol	\N
12	1	\N	t	f	0	n	symbol	\N
13	3	\N	f	f	0	e1	symbol	\\hat{i}
14	3	\N	f	f	0	e2	symbol	\\hat{j}
15	3	\N	f	f	0	e3	symbol	\\hat{k}
16	4	14	f	f	0	r	symbol	\N
17	4	15	f	f	0	theta	latex	\\theta
18	4	16	f	f	1	sin	latex	\\sin$0
19	4	17	f	f	1	cos	latex	\\cos$0
20	5	\N	t	f	0	x	symbol	\N
21	5	\N	t	f	0	y	symbol	\N
22	5	\N	t	f	1	f	abbreviation	\N
23	5	18	f	f	1	d	symbol	\\Delta$0
24	5	19	f	f	3	lim	latex	\\lim_{$0\\to$1}$2
25	5	20	f	f	2	diff	abbreviation	\\frac{\\partial}{\\partial$0}$1
26	1	22	f	f	1	abs	abbreviation	\\left|$0\\right|
\.


--
-- Name: function_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('function_id_seq', 26, true);


--
-- Data for Name: language; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY language (id, code) FROM stdin;
1	en_US
2	nl_NL
\.


--
-- Name: language_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('language_id_seq', 2, true);


--
-- Data for Name: operator; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY operator (id, function_id, precedence_level, associativity, operator_type, "character", editor_template) FROM stdin;
1	1	1	ltr	infix	=	{}={}
2	2	2	ltr	infix	+	{}+{}
3	3	2	ltr	infix	-	{}-{}
4	4	3	ltr	infix	*	{}\\cdot{}
5	5	3	ltr	infix	/	{}\\div{}
6	6	4	rtl	infix	^	^{$0}
7	7	5	ltr	prefix	~	-
8	8	6	rtl	postfix	!	!\\,
\.


--
-- Name: operator_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('operator_id_seq', 8, true);


--
-- Data for Name: proof; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY proof (id, first_step_id, last_step_id) FROM stdin;
1	1	4
2	5	7
3	8	11
4	12	14
5	15	17
6	18	21
7	22	32
8	33	38
9	39	41
10	42	44
11	45	59
\.


--
-- Name: proof_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('proof_id_seq', 11, true);


--
-- Data for Name: rule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY rule (id, proof_id, left_expression_id, right_expression_id, left_array_data, right_array_data) FROM stdin;
1	\N	4	5	{576332304,4,2,2,11,198119638,3,9,251955836,4,7,1,3,358130610,3,10}	{725194104,4,3,2,6,198119638,3,9,358130610,3,10}
2	\N	9	11	{755105816,4,2,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{528846700,4,4,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
3	\N	12	15	{304733658,4,7,1,3,198119638,3,9}	{691054416,4,4,2,11,205680372,4,7,1,3,5,1,1,198119638,3,9}
4	\N	16	1	{510478350,4,6,2,6,198119638,3,9,5,1,1}	{198119638,3,9}
5	\N	19	20	{71005026,4,4,2,22,695795496,4,6,2,6,198119638,3,9,358130610,3,10,622151856,4,6,2,6,198119638,3,9,971369676,3,11}	{491848602,4,6,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
6	\N	23	30	{518681770,4,25,2,11,801036408,3,20,647388986,5,22,1,3,801036408,3,20}	{259565444,4,24,3,58,10394894,4,23,1,3,801036408,3,20,1,1,0,1070033562,4,5,2,42,609969986,4,3,2,29,177948780,5,22,1,16,241161002,4,2,2,11,801036408,3,20,10394894,4,23,1,3,801036408,3,20,647388986,5,22,1,3,801036408,3,20,10394894,4,23,1,3,801036408,3,20}
7	\N	32	34	{696138698,4,1,2,14,767099948,4,2,2,6,198119638,3,9,358130610,3,10,971369676,3,11}	{136942074,4,1,2,14,198119638,3,9,270562032,4,3,2,6,971369676,3,11,358130610,3,10}
8	2	32	43	{696138698,4,1,2,14,767099948,4,2,2,6,198119638,3,9,358130610,3,10,971369676,3,11}	{473198860,4,1,2,14,358130610,3,10,328348816,4,3,2,6,971369676,3,11,198119638,3,9}
9	1	35	39	{736185540,4,4,2,6,198119638,3,9,198119638,3,9}	{1068305054,4,6,2,6,198119638,3,9,9,1,2}
10	3	46	11	{16837742,4,2,2,22,646841570,4,4,2,6,358130610,3,10,198119638,3,9,448454688,4,4,2,6,971369676,3,11,198119638,3,9}	{528846700,4,4,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
11	\N	1	48	{198119638,3,9}	{955462542,4,4,2,6,5,1,1,198119638,3,9}
12	4	9	49	{755105816,4,2,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{369792538,4,4,2,14,416255908,4,2,2,6,358130610,3,10,971369676,3,11,198119638,3,9}
13	5	46	49	{16837742,4,2,2,22,646841570,4,4,2,6,358130610,3,10,198119638,3,9,448454688,4,4,2,6,971369676,3,11,198119638,3,9}	{369792538,4,4,2,14,416255908,4,2,2,6,358130610,3,10,971369676,3,11,198119638,3,9}
14	6	50	53	{798769316,4,2,2,6,198119638,3,9,198119638,3,9}	{87245626,4,4,2,6,9,1,2,198119638,3,9}
15	7	54	79	{618267248,4,6,2,14,767099948,4,2,2,6,198119638,3,9,358130610,3,10,9,1,2}	{337764186,4,2,2,46,30927278,4,2,2,30,1068305054,4,6,2,6,198119638,3,9,9,1,2,947390454,4,4,2,14,87245626,4,4,2,6,9,1,2,198119638,3,9,358130610,3,10,1061973566,4,6,2,6,358130610,3,10,9,1,2}
16	\N	80	25	{99079404,4,4,2,6,1,1,0,198119638,3,9}	{1,1,0}
17	8	81	25	{631223668,4,3,2,6,198119638,3,9,198119638,3,9}	{1,1,0}
18	\N	87	1	{1020690818,4,2,2,6,198119638,3,9,1,1,0}	{198119638,3,9}
19	9	88	1	{670663792,4,2,2,6,1,1,0,198119638,3,9}	{198119638,3,9}
20	\N	89	1	{701243338,4,5,2,14,507440212,4,4,2,6,198119638,3,9,358130610,3,10,358130610,3,10}	{198119638,3,9}
21	10	90	1	{529660182,4,5,2,14,646841570,4,4,2,6,358130610,3,10,198119638,3,9,358130610,3,10}	{198119638,3,9}
22	\N	93	96	{566635098,4,24,3,17,198119638,3,9,358130610,3,10,237948570,4,2,2,6,801036408,3,20,208212430,3,21}	{671542814,4,2,2,28,480104780,4,24,3,9,198119638,3,9,358130610,3,10,801036408,3,20,270136248,4,24,3,9,198119638,3,9,358130610,3,10,208212430,3,21}
23	\N	97	25	{870341676,4,24,3,9,198119638,3,9,1,1,0,198119638,3,9}	{1,1,0}
24	\N	98	7	{838931994,4,24,3,9,198119638,3,9,358130610,3,10,971369676,3,11}	{971369676,3,11}
\.


--
-- Name: rule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('rule_id_seq', 24, true);


--
-- Data for Name: step; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY step (id, previous_id, expression_id, "position", step_type, proof_id, rule_id, rearrange) FROM stdin;
1	\N	35	0	set	\N	\N	\N
2	1	36	2	rule_invert	\N	4	\N
3	2	37	1	rule_invert	\N	4	\N
4	3	39	0	rule_normal	\N	5	\N
5	\N	32	0	set	\N	\N	\N
6	5	41	1	rearrange	\N	\N	{1,0}
7	6	43	0	rule_normal	\N	7	\N
8	\N	46	0	set	\N	\N	\N
9	8	47	4	rearrange	\N	\N	{1,0}
10	9	9	1	rearrange	\N	\N	{1,0}
11	10	11	0	rule_normal	\N	2	\N
12	\N	9	0	set	\N	\N	\N
13	12	11	0	rule_normal	\N	2	\N
14	13	49	0	rearrange	\N	\N	{1,0}
15	\N	46	0	set	\N	\N	\N
16	15	11	0	rule_normal	\N	10	\N
17	16	49	0	rearrange	\N	\N	{1,0}
18	\N	50	0	set	\N	\N	\N
19	18	51	2	rule_normal	\N	11	\N
20	19	52	1	rule_normal	\N	11	\N
21	20	53	0	rule_normal	\N	13	\N
22	\N	54	0	set	\N	\N	\N
23	22	55	0	rule_invert	\N	9	\N
24	23	58	0	rule_invert	\N	10	\N
25	24	61	6	rule_invert	\N	2	\N
26	25	63	1	rule_invert	\N	2	\N
27	26	66	0	rearrange	\N	\N	{0,1,2,-1,-1,3}
28	27	69	9	rearrange	\N	\N	{1,0}
29	28	71	12	rule_normal	\N	9	\N
30	29	74	5	rule_normal	\N	14	\N
31	30	76	2	rule_normal	\N	9	\N
32	31	79	5	rearrange	\N	\N	{0,1,-1,2}
33	\N	81	0	set	\N	\N	\N
34	33	82	0	rule_invert	\N	1	\N
35	34	85	2	rule_normal	\N	3	\N
36	35	86	1	rule_normal	\N	11	\N
37	36	80	0	rule_normal	\N	13	\N
38	37	25	0	rule_normal	\N	16	\N
39	\N	88	0	set	\N	\N	\N
40	39	87	0	rearrange	\N	\N	{1,0}
41	40	1	0	rule_normal	\N	18	\N
42	\N	90	0	set	\N	\N	\N
43	42	89	1	rearrange	\N	\N	{1,0}
44	43	1	0	rule_normal	\N	20	\N
45	\N	100	0	set	\N	\N	\N
46	45	104	0	rule_normal	\N	6	\N
47	46	112	6	rule_normal	\N	15	\N
48	47	116	5	rule_invert	\N	1	\N
49	48	121	5	rearrange	\N	\N	{0,3,-1,1,-1,2}
50	49	125	21	rule_invert	\N	9	\N
51	50	130	7	rule_normal	\N	1	\N
52	51	134	7	rule_normal	\N	17	\N
53	52	137	6	rule_normal	\N	19	\N
54	53	141	5	rule_normal	\N	10	\N
55	54	142	4	rule_normal	\N	21	\N
56	55	145	0	rule_normal	\N	22	\N
57	56	146	8	rule_normal	\N	23	\N
58	57	147	1	rule_normal	\N	24	\N
59	58	105	0	rule_normal	\N	18	\N
\.


--
-- Name: step_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('step_id_seq', 59, true);


--
-- Data for Name: subject; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY subject (id, descriptor_id) FROM stdin;
1	1
2	2
3	3
4	4
5	5
6	21
\.


--
-- Name: subject_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('subject_id_seq', 6, true);


--
-- Data for Name: translation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY translation (id, descriptor_id, language_id, content) FROM stdin;
1	1	1	Basic Algebra
2	2	1	Combinatorics
3	3	1	Vector Algebra
4	4	1	Trigonometry
5	5	1	Calculus
6	6	1	Equality
7	7	1	Add
8	8	1	Subtract
9	9	1	Multiply
10	10	1	Divide
11	11	1	Power
12	12	1	Negate
13	13	1	Factorial
14	14	1	Radius
15	15	1	Theta
16	16	1	Sine
17	17	1	Cosine
18	18	1	Delta
19	19	1	Limit
20	20	1	Differential
21	1	2	Basis algebra
22	2	2	Combinatoriek
23	3	2	Vectoralgebra
24	4	2	Trigonometrie
25	5	2	Calculus
26	6	2	Gelijkheid
27	7	2	Optellen
28	8	2	Aftrekken
29	9	2	Vermenigvuldigen
30	10	2	Delen
31	11	2	Macht
32	12	2	Omkeren
33	13	2	Factorial
34	14	2	Radius
35	15	2	Theta
36	16	2	Sinus
37	17	2	Cosinus
38	18	2	Delta
39	19	2	Limiet
40	20	2	Differentiaal
41	21	1	Classical Mechanics
42	22	1	Absolute Value
\.


--
-- Name: translation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('translation_id_seq', 42, true);


--
-- Name: definition definition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition
    ADD CONSTRAINT definition_pkey PRIMARY KEY (id);


--
-- Name: definition definition_rule_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition
    ADD CONSTRAINT definition_rule_id_key UNIQUE (rule_id);


--
-- Name: descriptor descriptor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY descriptor
    ADD CONSTRAINT descriptor_pkey PRIMARY KEY (id);


--
-- Name: expression expression_data_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression
    ADD CONSTRAINT expression_data_key UNIQUE (data);


--
-- Name: expression expression_hash_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression
    ADD CONSTRAINT expression_hash_key UNIQUE (hash);


--
-- Name: expression expression_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression
    ADD CONSTRAINT expression_pkey PRIMARY KEY (id);


--
-- Name: function function_descriptor_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_descriptor_id_key UNIQUE (descriptor_id);


--
-- Name: function function_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_pkey PRIMARY KEY (id);


--
-- Name: function function_subject_id_latex_template_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_subject_id_latex_template_key UNIQUE (subject_id, latex_template);


--
-- Name: language language_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_code_key UNIQUE (code);


--
-- Name: language language_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_pkey PRIMARY KEY (id);


--
-- Name: operator operator_character_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_character_key UNIQUE ("character");


--
-- Name: operator operator_editor_template_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_editor_template_key UNIQUE (editor_template);


--
-- Name: operator operator_function_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_function_id_key UNIQUE (function_id);


--
-- Name: operator operator_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_pkey PRIMARY KEY (id);


--
-- Name: proof proof_first_step_id_last_step_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_first_step_id_last_step_id_key UNIQUE (first_step_id, last_step_id);


--
-- Name: proof proof_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_pkey PRIMARY KEY (id);


--
-- Name: rule rule_left_expression_id_right_expression_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_left_expression_id_right_expression_id_key UNIQUE (left_expression_id, right_expression_id);


--
-- Name: rule rule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_pkey PRIMARY KEY (id);


--
-- Name: step step_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_pkey PRIMARY KEY (id);


--
-- Name: subject subject_descriptor_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_descriptor_id_key UNIQUE (descriptor_id);


--
-- Name: subject subject_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_pkey PRIMARY KEY (id);


--
-- Name: translation translation_language_id_content_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_language_id_content_key UNIQUE (language_id, content);


--
-- Name: translation translation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_pkey PRIMARY KEY (id);


--
-- Name: expression_functions_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX expression_functions_index ON expression USING gin (functions);


--
-- Name: function_keyword_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX function_keyword_index ON function USING btree (keyword);


--
-- Name: definition definition_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition
    ADD CONSTRAINT definition_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES rule(id);


--
-- Name: function function_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: function function_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subject(id);


--
-- Name: operator operator_function_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_function_id_fkey FOREIGN KEY (function_id) REFERENCES function(id);


--
-- Name: proof proof_first_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_first_step_id_fkey FOREIGN KEY (first_step_id) REFERENCES step(id);


--
-- Name: proof proof_last_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_last_step_id_fkey FOREIGN KEY (last_step_id) REFERENCES step(id);


--
-- Name: rule rule_left_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_left_expression_id_fkey FOREIGN KEY (left_expression_id) REFERENCES expression(id);


--
-- Name: rule rule_proof_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_proof_id_fkey FOREIGN KEY (proof_id) REFERENCES proof(id);


--
-- Name: rule rule_right_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_right_expression_id_fkey FOREIGN KEY (right_expression_id) REFERENCES expression(id);


--
-- Name: step step_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_expression_id_fkey FOREIGN KEY (expression_id) REFERENCES expression(id);


--
-- Name: step step_previous_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_previous_id_fkey FOREIGN KEY (previous_id) REFERENCES step(id);


--
-- Name: step step_proof_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_proof_id_fkey FOREIGN KEY (proof_id) REFERENCES proof(id);


--
-- Name: step step_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES rule(id);


--
-- Name: subject subject_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: translation translation_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: translation translation_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_language_id_fkey FOREIGN KEY (language_id) REFERENCES language(id);


--
-- Name: plperl; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON LANGUAGE plperl TO eqdb;


--
-- Name: definition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE definition TO eqdb;


--
-- Name: definition_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE definition_id_seq TO eqdb;


--
-- Name: descriptor; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE descriptor TO eqdb;


--
-- Name: descriptor_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE descriptor_id_seq TO eqdb;


--
-- Name: expression; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE expression TO eqdb;


--
-- Name: expression_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE expression_id_seq TO eqdb;


--
-- Name: function; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE function TO eqdb;


--
-- Name: function.subject_id; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(subject_id) ON TABLE function TO eqdb;


--
-- Name: function_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE function_id_seq TO eqdb;


--
-- Name: language; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE language TO eqdb;


--
-- Name: language_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE language_id_seq TO eqdb;


--
-- Name: operator; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE operator TO eqdb;


--
-- Name: operator_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE operator_id_seq TO eqdb;


--
-- Name: proof; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE proof TO eqdb;


--
-- Name: proof_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE proof_id_seq TO eqdb;


--
-- Name: rule; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE rule TO eqdb;


--
-- Name: rule_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE rule_id_seq TO eqdb;


--
-- Name: step; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE step TO eqdb;


--
-- Name: step_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE step_id_seq TO eqdb;


--
-- Name: subject; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE subject TO eqdb;


--
-- Name: subject_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE subject_id_seq TO eqdb;


--
-- Name: translation; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE translation TO eqdb;


--
-- Name: translation_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE translation_id_seq TO eqdb;


--
-- PostgreSQL database dump complete
--

\connect postgres

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.2
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgres; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE postgres IS 'default administrative connection database';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- PostgreSQL database dump complete
--

\connect template1

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.2
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: template1; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE template1 IS 'default template for new databases';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database cluster dump complete
--

