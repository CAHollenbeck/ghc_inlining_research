%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1996
%
\section[TyCon]{The @TyCon@ datatype}

\begin{code}
#include "HsVersions.h"

module TyCon(
	TyCon(..), 	-- NB: some pals need to see representation

	Arity(..), ConsVisible(..), NewOrData(..),

	isFunTyCon, isPrimTyCon, isVisibleDataTyCon,

	mkDataTyCon,
	mkFunTyCon,
	mkPrimTyCon,
	mkSpecTyCon,
	mkTupleTyCon,

	mkSynTyCon,

	getTyConKind,
	getTyConUnique,
	getTyConTyVars,
	getTyConDataCons,
	getTyConDerivings,
	getSynTyConArity,

        maybeTyConSingleCon,
	isEnumerationTyCon,
	derivedFor
) where

CHK_Ubiq()	-- debugging consistency check
import NameLoop	-- for paranoia checking

import TyLoop		( Type(..), GenType,
			  Class(..), GenClass,
			  Id(..), GenId,
			  mkTupleCon, getDataConSig,
			  specMaybeTysSuffix
			)

import TyVar		( GenTyVar, alphaTyVars, alphaTyVar, betaTyVar )
import Usage		( GenUsage, Usage(..) )
import Kind		( Kind, mkBoxedTypeKind, mkArrowKind, resultKind, argKind )
import PrelMods		( pRELUDE_BUILTIN )

import Maybes
import NameTypes	( FullName )
import Unique		( Unique, funTyConKey, mkTupleTyConUnique )
import Outputable
import Pretty		( Pretty(..), PrettyRep )
import PprStyle		( PprStyle )
import SrcLoc		( SrcLoc, mkBuiltinSrcLoc )
import Util		( panic, panic#, nOfThem, isIn, Ord3(..) )
\end{code}

\begin{code}
type Arity = Int

data TyCon
  = FunTyCon		-- Kind = Type -> Type -> Type

  | DataTyCon	Unique{-TyConKey-}
		Kind
		FullName
		[TyVar]
		[(Class,Type)]	-- Its context
		[Id]		-- Its data constructors, with fully polymorphic types
		[Class]		-- Classes which have derived instances
		ConsVisible
		NewOrData

  | TupleTyCon	Arity	-- just a special case of DataTyCon
			-- Kind = BoxedTypeKind
			--      -> ... (n times) ...
			--	-> BoxedTypeKind
			--      -> BoxedTypeKind

  | PrimTyCon		-- Primitive types; cannot be defined in Haskell
	Unique		-- Always unboxed; hence never represented by a closure
	FullName	-- Often represented by a bit-pattern for the thing
	Kind		-- itself (eg Int#), but sometimes by a pointer to

  | SpecTyCon		-- A specialised TyCon; eg (Arr# Int#), or (List Int#)
	TyCon
	[Maybe Type]	-- Specialising types

	-- 	OLD STUFF ABOUT Array types.  Use SpecTyCon instead
	-- ([PrimRep] -> PrimRep) -- a heap-allocated object (eg ArrInt#).
	-- The primitive types Arr# and StablePtr# have
	-- parameters (hence arity /= 0); but the rest don't.
	-- Only arrays use the list in a non-trivial way.
	-- Length of that list must == arity.

  | SynTyCon
	Unique
	FullName
	Kind
	Arity
	[TyVar]		-- Argument type variables
	Type		-- Right-hand side, mentioning these type vars.
			-- Acts as a template for the expansion when
			-- the tycon is applied to some types.

data ConsVisible
  = ConsVisible	    -- whether or not data constructors are visible
  | ConsInvisible   -- outside their TyCon's defining module.

data NewOrData
  = NewType	    -- "newtype Blah ..."
  | DataType	    -- "data Blah ..."
\end{code}

\begin{code}
mkFunTyCon	= FunTyCon
mkDataTyCon	= DataTyCon
mkTupleTyCon	= TupleTyCon
mkPrimTyCon	= PrimTyCon
mkSpecTyCon	= SpecTyCon
mkSynTyCon	= SynTyCon

isFunTyCon FunTyCon = True
isFunTyCon _ = False

isPrimTyCon (PrimTyCon _ _ _) = True
isPrimTyCon _ = False

isVisibleDataTyCon (DataTyCon _ _ _ _ _ _ _ ConsVisible _) = True
isVisibleDataTyCon _ = False
\end{code}

\begin{code}
-- Special cases to avoid reconstructing lots of kinds
kind1 = mkBoxedTypeKind `mkArrowKind` mkBoxedTypeKind
kind2 = mkBoxedTypeKind `mkArrowKind` kind1

getTyConKind :: TyCon -> Kind
getTyConKind FunTyCon 			      = kind2
getTyConKind (DataTyCon _ kind _ _ _ _ _ _ _) = kind
getTyConKind (PrimTyCon _ _ kind) 	      = kind

getTyConKind (SpecTyCon tc tys)
  = spec (getTyConKind tc) tys
   where
    spec kind []	      = kind
    spec kind (Just _  : tys) = spec (resultKind kind) tys
    spec kind (Nothing : tys) =
      argKind kind `mkArrowKind` spec (resultKind kind) tys

getTyConKind (TupleTyCon n)
  = mkArrow n
   where
    mkArrow 0 = mkBoxedTypeKind
    mkArrow 1 = kind1
    mkArrow 2 = kind2
    mkArrow n = mkBoxedTypeKind `mkArrowKind` mkArrow (n-1)
\end{code}

\begin{code}
getTyConUnique :: TyCon -> Unique
getTyConUnique FunTyCon			        = funTyConKey
getTyConUnique (DataTyCon uniq _ _ _ _ _ _ _ _) = uniq
getTyConUnique (TupleTyCon a) 			= mkTupleTyConUnique a
getTyConUnique (PrimTyCon uniq _ _) 	        = uniq
getTyConUnique (SynTyCon uniq _ _ _ _ _)        = uniq
getTyConUnique (SpecTyCon _ _ ) 	        = panic "getTyConUnique:SpecTyCon"
\end{code}

\begin{code}
getTyConTyVars :: TyCon -> [TyVar]
getTyConTyVars FunTyCon			       = [alphaTyVar,betaTyVar]
getTyConTyVars (DataTyCon _ _ _ tvs _ _ _ _ _) = tvs
getTyConTyVars (TupleTyCon arity) 	       = take arity alphaTyVars
getTyConTyVars (SynTyCon _ _ _ _ tvs _)        = tvs
getTyConTyVars (PrimTyCon _ _ _) 	       = panic "getTyConTyVars:PrimTyCon"
getTyConTyVars (SpecTyCon _ _ ) 	       = panic "getTyConTyVars:SpecTyCon"
\end{code}

\begin{code}
getTyConDataCons :: TyCon -> [Id]
getTyConDataCons (DataTyCon _ _ _ _ _ data_cons _ _ _) = data_cons
getTyConDataCons (TupleTyCon a)			       = [mkTupleCon a]
\end{code}

\begin{code}
getTyConDerivings :: TyCon -> [Class]
getTyConDerivings (DataTyCon _ _ _ _ _ _ derivs _ _) = derivs
\end{code}

\begin{code}
getSynTyConArity :: TyCon -> Maybe Arity
getSynTyConArity (SynTyCon _ _ _ arity _ _) = Just arity
getSynTyConArity other			    = Nothing
\end{code}

\begin{code}
maybeTyConSingleCon :: TyCon -> Maybe Id
maybeTyConSingleCon (TupleTyCon arity)	             = Just (mkTupleCon arity)
maybeTyConSingleCon (DataTyCon _ _ _ _ _ [c] _ _ _)  = Just c
maybeTyConSingleCon (DataTyCon _ _ _ _ _ _   _ _ _)  = Nothing
maybeTyConSingleCon (PrimTyCon _ _ _)	             = Nothing
maybeTyConSingleCon (SpecTyCon tc tys)               = panic "maybeTyConSingleCon:SpecTyCon"
						     -- requires DataCons of TyCon

isEnumerationTyCon (TupleTyCon arity)
  = arity == 0
isEnumerationTyCon (DataTyCon _ _ _ _ _ data_cons _ _ _)
  = not (null data_cons) && all is_nullary data_cons
  where
    is_nullary con = case (getDataConSig con) of { (_,_, arg_tys, _) ->
		     null arg_tys }
\end{code}

@derivedFor@ reports if we have an {\em obviously}-derived instance
for the given class/tycon.  Of course, you might be deriving something
because it a superclass of some other obviously-derived class --- this
function doesn't deal with that.

ToDo: what about derivings for specialised tycons !!!

\begin{code}
derivedFor :: Class -> TyCon -> Bool
derivedFor clas (DataTyCon _ _ _ _ _ _ derivs _ _) = isIn "derivedFor" clas derivs
derivedFor clas something_weird		           = False
\end{code}

%************************************************************************
%*									*
\subsection[TyCon-instances]{Instance declarations for @TyCon@}
%*									*
%************************************************************************

@TyCon@s are compared by comparing their @Unique@s.

The strictness analyser needs @Ord@. It is a lexicographic order with
the property @(a<=b) || (b<=a)@.

\begin{code}
instance Ord3 TyCon where
  cmp FunTyCon		            FunTyCon		          = EQ_
  cmp (DataTyCon a _ _ _ _ _ _ _ _) (DataTyCon b _ _ _ _ _ _ _ _) = a `cmp` b
  cmp (SynTyCon a _ _ _ _ _)        (SynTyCon b _ _ _ _ _)        = a `cmp` b
  cmp (TupleTyCon a)	            (TupleTyCon b)	          = a `cmp` b
  cmp (PrimTyCon a _ _)		    (PrimTyCon b _ _)	          = a `cmp` b
  cmp (SpecTyCon tc1 mtys1)	    (SpecTyCon tc2 mtys2)
    = panic# "cmp on SpecTyCons" -- case (tc1 `cmp` tc2) of { EQ_ -> mtys1 `cmp` mtys2; xxx -> xxx }

    -- now we *know* the tags are different, so...
  cmp other_1 other_2
    | tag1 _LT_ tag2 = LT_
    | otherwise      = GT_
    where
      tag1 = tag_TyCon other_1
      tag2 = tag_TyCon other_2
      tag_TyCon FunTyCon    		      = ILIT(1)
      tag_TyCon (DataTyCon _ _ _ _ _ _ _ _ _) = ILIT(2)
      tag_TyCon (TupleTyCon _)		      = ILIT(3)
      tag_TyCon (PrimTyCon  _ _ _)	      = ILIT(4)
      tag_TyCon (SpecTyCon  _ _) 	      = ILIT(5)

instance Eq TyCon where
    a == b = case (a `cmp` b) of { EQ_ -> True;   _ -> False }
    a /= b = case (a `cmp` b) of { EQ_ -> False;  _ -> True  }

instance Ord TyCon where
    a <= b = case (a `cmp` b) of { LT_ -> True;  EQ_ -> True;  GT__ -> False }
    a <	 b = case (a `cmp` b) of { LT_ -> True;  EQ_ -> False; GT__ -> False }
    a >= b = case (a `cmp` b) of { LT_ -> False; EQ_ -> True;  GT__ -> True  }
    a >	 b = case (a `cmp` b) of { LT_ -> False; EQ_ -> False; GT__ -> True  }
    _tagCmp a b = case (a `cmp` b) of { LT_ -> _LT; EQ_ -> _EQ; GT__ -> _GT }
\end{code}

\begin{code}
instance NamedThing TyCon where
    getExportFlag tc = case get_name tc of
			 Nothing   -> NotExported
			 Just name -> getExportFlag name


    isLocallyDefined tc = case get_name tc of
			    Nothing   -> False
			    Just name -> isLocallyDefined name

    getOrigName FunTyCon		= (pRELUDE_BUILTIN, SLIT("(->)"))
    getOrigName (TupleTyCon a)		= (pRELUDE_BUILTIN, _PK_ ("Tuple" ++ show a))
    getOrigName (SpecTyCon tc tys)	= let (m,n) = getOrigName tc in
					  (m, n _APPEND_ specMaybeTysSuffix tys)
    getOrigName	other_tc           	= getOrigName (expectJust "tycon1" (get_name other_tc))

    getOccurrenceName  FunTyCon		= SLIT("(->)")
    getOccurrenceName (TupleTyCon 0)	= SLIT("()")
    getOccurrenceName (TupleTyCon a)	= _PK_ ( "(" ++ nOfThem (a-1) ',' ++ ")" )
    getOccurrenceName (SpecTyCon tc tys)= getOccurrenceName tc _APPEND_ specMaybeTysSuffix tys
    getOccurrenceName other_tc          = getOccurrenceName (expectJust "tycon2" (get_name other_tc))

    getInformingModules	tc = case get_name tc of
				Nothing   -> panic "getInformingModule:TyCon"
				Just name -> getInformingModules name

    getSrcLoc tc = case get_name tc of
		     Nothing   -> mkBuiltinSrcLoc
		     Just name -> getSrcLoc name

    getItsUnique tycon = getTyConUnique tycon

    fromPreludeCore tc = case get_name tc of
			   Nothing   -> True
			   Just name -> fromPreludeCore name
\end{code}

Emphatically un-exported:

\begin{code}
get_name (DataTyCon _ _ n _ _ _ _ _ _) = Just n
get_name (PrimTyCon _ n _)	       = Just n
get_name (SpecTyCon tc _)	       = get_name tc
get_name (SynTyCon _ n _ _ _ _)	       = Just n
get_name other			       = Nothing
\end{code}

