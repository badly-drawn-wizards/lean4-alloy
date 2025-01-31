/-
Copyright (c) 2023 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Alloy.C.Syntax
import Alloy.C.Translator
import Alloy.Util.OpaqueType
import Lean.Compiler.NameMangling

namespace Alloy.C
open Lean Elab Parser Command

/-- The configuration an Alloy C `extern_type` declaration. -/
structure ExternType extends Translator where
  /--
  The name to give the generated C wrapper function.
  If anonymous, an appropriate name will also be generated.
  -/
  toLean := .anonymous
   /--
  The name to give the generated C unwrapper function.
  If anonymous, an appropriate name will also be generated.
  -/
  ofLean := .anonymous
  /--
  The name to give the generated `lean_external_class` declaration.
  If anonymous, an appropriate name will also be generated.
  -/
  externalClass : Name := .anonymous
  /--
  The name of C foreach function of the external class.
  If anonymous, an appropriately named no-op foreach function will be generated.
  -/
  foreach : Name := .anonymous
  /-- The name of C finalizer function of the external class.  -/
  finalize : Name

unsafe def evalExternTypeUnsafe (stx : Syntax) : TermElabM ExternType :=
  Term.evalTerm ExternType (mkConst ``ExternType) stx

@[implemented_by evalExternTypeUnsafe]
opaque evalExternType (stx : Syntax) : TermElabM ExternType

/--
Declare a type to be represented by a `lean_external_class` object.
The generated C definition can be configured through an `ExternType` term.

```lean
alloy c extern_type LeanType => c_type := <config term>
```
-/
scoped syntax (name := externType)
"alloy " &"c " &"extern_type " ident " => " cSpec+ " := " term : command

elab_rules : command
| `(externType| alloy c extern_type $id => $cTy* := $cfg) => do
  let ref ← getRef
  let cfg ← liftTermElabM <| evalExternType cfg
  let name ← resolveGlobalConstNoOverloadWithInfo id
  let cls := mkIdent <| if cfg.externalClass.isAnonymous then
    .mkSimple <| "_alloy_g_class_" ++ name.mangle else cfg.externalClass
  let toLean := if cfg.toLean.isAnonymous then
    .mkSimple <| "_alloy_to_" ++ name.mangle else cfg.toLean
  let ofLean := if cfg.ofLean.isAnonymous then
    .mkSimple <| "_alloy_of_" ++ name.mangle else cfg.ofLean
  let foreach := mkIdent <| if cfg.foreach.isAnonymous then
    .mkSimple <| "_alloy_foreach_" ++ name.mangle else cfg.foreach
  let finalize := mkIdent cfg.finalize
  let cmd ← MonadRef.withRef .missing `(
    alloy c section
    static lean_external_class * $cls:ident = NULL;
    static inline lean_obj_res $(mkIdent toLean):ident($cTy:cDeclSpec* * o) {
      if ($cls == NULL) {
        $cls:ident = lean_register_external_class($finalize, $foreach);
      }
      return lean_alloc_external($cls, o);
    }
    static inline $cTy* * $(mkIdent ofLean):ident(b_lean_obj_arg o) {
      return ($cTy* *)(lean_get_external_data(o));
    }
    end
  )
  let cmd ←
    if cfg.foreach.isAnonymous then
      MonadRef.withRef .missing  `(
        alloy c section
        static inline void $foreach:ident(void * ptr, b_lean_obj_arg f) {}
        end
        $cmd
      )
    else
      pure cmd
  withMacroExpansion ref cmd <| elabCommand cmd
  modifyEnv fun env => translatorExt.insert env name {toLean, ofLean}


/--
Declare an `opaque_type` represented by a `lean_external_class` object.
The generated C definition can be configured through an `ExternType` term.

```lean
alloy c opaque_extern_type LeanType (..) : Type u => c_type := <config term>
```
-/
scoped syntax (name := opaqueExternType)
(docComment)? (Term.attributes)? (visibility)? «unsafe»?
"alloy " &"c " &"opaque_extern_type " declId binders (typeLvSpec)?
  " => " cSpec+ " := " term : command

macro_rules
| `(opaqueExternType| $(doc?)? $(attrs?)? $(vis?)? $[unsafe%$uTk?]?
  alloy c opaque_extern_type $declId $bs* $[$ty]? => $cTy* := $cfg) => do
  let id : Ident := ⟨declId.raw[0]⟩
  `(
    $[$doc?:docComment]? $(attrs?)? $(vis?)? $[unsafe%$uTk?]? opaque_type $declId $bs* $[$ty]?
    alloy c extern_type $id => $cTy* := $cfg
  )
