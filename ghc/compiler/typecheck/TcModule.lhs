%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1996
%
\section[TcModule]{Typechecking a whole module}

\begin{code}
#include "HsVersions.h"

module TcModule (
	tcModule
    ) where

import Ubiq

import HsSyn		( HsModule(..), HsBinds(..), Bind, HsExpr,
			  TyDecl, SpecDataSig, ClassDecl, InstDecl,
			  SpecInstSig, DefaultDecl, Sig, Fake, InPat,
 			  FixityDecl, IE, ImportedInterface )
import RnHsSyn		( RenamedHsModule(..), RenamedFixityDecl(..) )
import TcHsSyn		( TypecheckedHsBinds(..), TypecheckedHsExpr(..),
			  TcIdOcc(..), zonkBinds, zonkInst, zonkId )

import TcMonad
import Inst		( Inst, plusLIE )
import TcBinds		( tcBindsAndThen )
import TcClassDcl	( tcClassDecls2 )
import TcDefaults	( tcDefaults )
import TcEnv		( tcExtendGlobalValEnv, getEnv_LocalIds,
			  getEnv_TyCons, getEnv_Classes)
import TcIfaceSig	( tcInterfaceSigs )
import TcInstDcls	( tcInstDecls1, tcInstDecls2 )
import TcInstUtil	( buildInstanceEnvs, InstInfo )
import TcSimplify	( tcSimplifyTop )
import TcTyClsDecls	( tcTyAndClassDecls1 )

import Bag		( listToBag )
import Class		( GenClass )
import Id		( GenId, isDataCon, isMethodSelId, idType )
import Maybes		( catMaybes )
import Name		( Name(..) )
import Outputable	( isExported )
import PrelInfo		( unitTy, mkPrimIoTy )
import Pretty
import RnUtils		( GlobalNameMappers(..), GlobalNameMapper(..) )
import TyCon		( TyCon )
import Type		( applyTyCon )
import Unify		( unifyTauTy )
import UniqFM		( lookupUFM_Directly, lookupWithDefaultUFM_Directly,
		          filterUFM, eltsUFM )
import Unique		( iOTyConKey, mainIdKey, mainPrimIOIdKey )
import Util


import FiniteMap	( emptyFM )
tycon_specs = emptyFM


\end{code}

\begin{code}
tcModule :: GlobalNameMappers		-- final renamer info for derivings
	 -> RenamedHsModule		-- input
	 -> TcM s ((TypecheckedHsBinds,	-- binds from class decls; does NOT
					-- include default-methods bindings
		    TypecheckedHsBinds,	-- binds from instance decls; INCLUDES
					-- class default-methods binds
		    TypecheckedHsBinds,	-- binds from value decls

		    [(Id, TypecheckedHsExpr)]), -- constant instance binds

		   ([RenamedFixityDecl], [Id], UniqFM TyCon, UniqFM Class, Bag InstInfo),
					-- things for the interface generator

		   (UniqFM TyCon, UniqFM Class),
					-- environments of info from this module only

		   FiniteMap TyCon [(Bool, [Maybe Type])],
					-- source tycon specialisation requests

		   PprStyle -> Pretty)	-- -ddump-deriving info

tcModule renamer_name_funs
	(HsModule mod_name exports imports fixities
		  ty_decls specdata_sigs cls_decls inst_decls specinst_sigs
		  default_decls val_decls sigs src_loc)

  = ASSERT(null imports)

    tcAddSrcLoc src_loc $	-- record where we're starting

	-- Tie the knot for inteface-file value declaration signatures
	-- This info is only used inside the knot for type-checking the
	-- pragmas, which is done lazily [ie failure just drops the pragma
	-- without having any global-failure effect].

    fixTc (\ ~(_, _, _, _, _, sig_ids) ->
	tcExtendGlobalValEnv sig_ids (

	-- The knot for instance information.  This isn't used at all
	-- till we type-check value declarations
	fixTc ( \ ~(rec_inst_mapper, _, _, _, _) ->

	     -- Type-check the type and class decls
	    trace "tcTyAndClassDecls:"	$
	    tcTyAndClassDecls1 rec_inst_mapper ty_decls_bag cls_decls_bag
					`thenTc` \ env ->

		-- Typecheck the instance decls, includes deriving
	    tcSetEnv env (
	    trace "tcInstDecls:"	$
	    tcInstDecls1 inst_decls_bag specinst_sigs
			 mod_name renamer_name_funs fixities 
	    )				`thenTc` \ (inst_info, deriv_binds, ddump_deriv) ->

	    buildInstanceEnvs inst_info	`thenTc` \ inst_mapper ->

	    returnTc (inst_mapper, env, inst_info, deriv_binds, ddump_deriv)

	) `thenTc` \ (_, env, inst_info, deriv_binds, ddump_deriv) ->
	tcSetEnv env (

	    -- Default declarations
	tcDefaults default_decls	`thenTc` \ defaulting_tys ->
	tcSetDefaultTys defaulting_tys 	( -- for the iface sigs...

	    -- Interface type signatures
	    -- We tie a knot so that the Ids read out of interfaces are in scope
	    --   when we read their pragmas.
	    -- What we rely on is that pragmas are typechecked lazily; if
	    --   any type errors are found (ie there's an inconsistency)
	    --   we silently discard the pragma
	tcInterfaceSigs sigs		`thenTc` \ sig_ids ->

	returnTc (env, inst_info, deriv_binds, ddump_deriv, defaulting_tys, sig_ids)

    )))) `thenTc` \ (env, inst_info, deriv_binds, ddump_deriv, defaulting_tys, _) ->

    tcSetEnv env (				-- to the end...
    tcSetDefaultTys defaulting_tys (		-- ditto

	-- Value declarations next.
	-- We also typecheck any extra binds that came out of the "deriving" process
    trace "tcBinds:"			$
    tcBindsAndThen
	(\ binds1 (binds2, thing) -> (binds1 `ThenBinds` binds2, thing))
	(val_decls `ThenBinds` deriv_binds)
	(	-- Second pass over instance declarations,
		-- to compile the bindings themselves.
	    tcInstDecls2  inst_info	`thenNF_Tc` \ (lie_instdecls, inst_binds) ->
	    tcClassDecls2 cls_decls_bag	`thenNF_Tc` \ (lie_clasdecls, cls_binds) ->
	    tcGetEnv			`thenNF_Tc` \ env ->
	    returnTc ( (EmptyBinds, (inst_binds, cls_binds, env)),
		       lie_instdecls `plusLIE` lie_clasdecls,
		       () ))

	`thenTc` \ ((val_binds, (inst_binds, cls_binds, final_env)), lie_alldecls, _) ->

    checkTopLevelIds mod_name final_env	`thenTc_`

	-- Deal with constant or ambiguous InstIds.  How could
	-- there be ambiguous ones?  They can only arise if a
	-- top-level decl falls under the monomorphism
	-- restriction, and no subsequent decl instantiates its
	-- type.  (Usually, ambiguous type variables are resolved
	-- during the generalisation step.)
    tcSimplifyTop lie_alldecls			`thenTc` \ const_insts ->
    let
        localids = getEnv_LocalIds final_env
	tycons   = getEnv_TyCons final_env
	classes  = getEnv_Classes final_env

	local_tycons  = filterUFM isLocallyDefined tycons
	local_classes = filterUFM isLocallyDefined classes

	exported_ids = [v | v <- eltsUFM localids,
		        isExported v && not (isDataCon v) && not (isMethodSelId v)]
    in
	-- Backsubstitution.  Monomorphic top-level decls may have
	-- been instantiated by subsequent decls, and the final
	-- simplification step may have instantiated some
	-- ambiguous types.  So, sadly, we need to back-substitute
	-- over the whole bunch of bindings.
    zonkBinds val_binds		 	`thenNF_Tc` \ val_binds' ->
    zonkBinds inst_binds	 	`thenNF_Tc` \ inst_binds' ->
    zonkBinds cls_binds	 		`thenNF_Tc` \ cls_binds' ->
    mapNF_Tc zonkInst const_insts 	`thenNF_Tc` \ const_insts' ->
    mapNF_Tc (zonkId.TcId) exported_ids	`thenNF_Tc` \ exported_ids' ->

	-- FINISHED AT LAST
    returnTc (
	(cls_binds', inst_binds', val_binds', const_insts'),

	     -- the next collection is just for mkInterface
	(fixities, exported_ids', tycons, classes, inst_info),

	(local_tycons, local_classes),

	tycon_specs,

	ddump_deriv
    )))
  where
    ty_decls_bag   = listToBag ty_decls
    cls_decls_bag  = listToBag cls_decls
    inst_decls_bag = listToBag inst_decls

\end{code}


%************************************************************************
%*									*
\subsection{Error checking code}
%*									*
%************************************************************************


checkTopLevelIds checks that Main.main or Main.mainPrimIO has correct type.

\begin{code}
checkTopLevelIds :: FAST_STRING -> TcEnv s -> TcM s ()
checkTopLevelIds mod final_env
  = if (mod /= SLIT("Main")) then
	returnTc ()
    else
	case (lookupUFM_Directly localids mainIdKey,
	      lookupUFM_Directly localids mainPrimIOIdKey) of 
	  (Just main, Nothing) -> tcAddErrCtxt mainCtxt $
		                  unifyTauTy ty_main (idType main)
	  (Nothing, Just prim) -> tcAddErrCtxt primCtxt $
		                  unifyTauTy ty_prim (idType prim)
	  (Just _ , Just _ )   -> failTc mainBothIdErr
	  (Nothing, Nothing)   -> failTc mainNoneIdErr
    where
      localids = getEnv_LocalIds final_env
      tycons   = getEnv_TyCons final_env

      io_tc    = lookupWithDefaultUFM_Directly tycons io_panic iOTyConKey
      io_panic = panic "TcModule: type IO not in scope"

      ty_main  = applyTyCon io_tc [unitTy]
      ty_prim  = mkPrimIoTy unitTy


mainCtxt sty
  = ppStr "main should have type IO ()"

primCtxt sty
  = ppStr "mainPrimIO should have type PrimIO ()"

mainBothIdErr sty
  = ppStr "module Main contains definitions for both main and mainPrimIO"

mainNoneIdErr sty
  = panic "ToDo: sort out mainIdKey"
 -- ppStr "module Main does not contain a definition for main (or mainPrimIO)"

\end{code}
