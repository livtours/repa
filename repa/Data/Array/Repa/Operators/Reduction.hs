{-# LANGUAGE BangPatterns, ExplicitForAll, TypeOperators, MagicHash #-}
{-# OPTIONS -fno-warn-orphans #-}
module Data.Array.Repa.Operators.Reduction
	( foldS,        foldP
	, foldAllS,     foldAllP
	, sumS,         sumP
	, sumAllS,      sumAllP
        , equalsS,      equalsP)
where
import Data.Array.Repa.Base
import Data.Array.Repa.Index
import Data.Array.Repa.Eval.Elt
import Data.Array.Repa.Repr.Unboxed
import Data.Array.Repa.Operators.Mapping        as R
import Data.Array.Repa.Shape		        as S
import qualified Data.Vector.Unboxed	        as V
import qualified Data.Vector.Unboxed.Mutable    as M
import Prelude				        hiding (sum)
import qualified Data.Array.Repa.Eval.Reduction as E
import System.IO.Unsafe
import GHC.Exts

-- foldS ----------------------------------------------------------------------
-- | Sequential reduction of the innermost dimension of an arbitrary rank array.
--
--   Combine this with `transpose` to fold any other dimension.
foldS 	:: (Shape sh, Elt a, Unbox a, Repr r a)
	=> (a -> a -> a)
	-> a
	-> Array r (sh :. Int) a
	-> Array U sh a

foldS f z arr
 = let  sh@(sz :. n') = extent arr
        !(I# n)       = n'
   in unsafePerformIO
    $ do mvec   <- M.unsafeNew (S.size sz)
         E.foldS mvec (\ix -> arr `unsafeIndex` fromIndex sh (I# ix)) f z n
         !vec   <- V.unsafeFreeze mvec
         return $ fromUnboxed sz vec
{-# INLINE [1] foldS #-}


-- | Parallel reduction of the innermost dimension of an arbitray rank array.
--
--   The first argument needs to be an associative sequential operator.
--   The starting element must be neutral with respect to the operator, for
--   example @0@ is neutral with respect to @(+)@ as @0 + a = a@.
--   These restrictions are required to support parallel evaluation, as the
--   starting element may be used multiple times depending on the number of threads.
foldP 	:: (Shape sh, Elt a, Unbox a, Repr r a)
	=> (a -> a -> a)
	-> a
	-> Array r (sh :. Int) a
	-> Array U sh a

foldP f z arr 
 = let  sh@(sz :. n) = extent arr
   in   case rank sh of
           -- specialise rank-1 arrays, else one thread does all the work.
           -- We can't match against the shape constructor,
           -- otherwise type error: (sz ~ Z)
           --
           1 -> let !vec = V.singleton $ foldAllP f z arr
                in  fromUnboxed sz vec

           _ -> unsafePerformIO 
              $ do mvec   <- M.unsafeNew (S.size sz)
                   E.foldP mvec (\ix -> arr `unsafeIndex` fromIndex sh ix) f z n
                   !vec   <- V.unsafeFreeze mvec
                   return $ fromUnboxed sz vec
{-# INLINE [1] foldP #-}


-- foldAll --------------------------------------------------------------------
-- | Sequential reduction of an array of arbitrary rank to a single scalar value.
--
foldAllS :: (Shape sh, Elt a, Unbox a, Repr r a)
	=> (a -> a -> a)
	-> a
	-> Array r sh a
	-> a

foldAllS f z arr 
 = arr `deepSeqArray`
   let  !ex     = extent arr
        !(I# n) = size ex
   in   E.foldAllS 
                (\ix -> arr `unsafeIndex` fromIndex ex (I# ix))
                f z n 
{-# INLINE [1] foldAllS #-}


-- | Parallel reduction of an array of arbitrary rank to a single scalar value.
--
--   The first argument needs to be an associative sequential operator.
--   The starting element must be neutral with respect to the operator,
--   for example @0@ is neutral with respect to @(+)@ as @0 + a = a@.
--   These restrictions are required to support parallel evaluation, as the
--   starting element may be used multiple times depending on the number of threads.
foldAllP :: (Shape sh, Elt a, Unbox a, Repr r a)
	 => (a -> a -> a)
	 -> a
	 -> Array r sh a
	 -> a

foldAllP f z arr 
 = let  sh = extent arr
        n  = size sh
   in   unsafePerformIO 
         $ E.foldAllP (\ix -> arr `unsafeIndex` fromIndex sh ix) f z n
{-# INLINE [1] foldAllP #-}


-- sum ------------------------------------------------------------------------
-- | Sequential sum the innermost dimension of an array.
sumS	:: (Shape sh, Num a, Elt a, Unbox a, Repr r a)
	=> Array r (sh :. Int) a
	-> Array U sh a
sumS = foldS (+) 0
{-# INLINE [3] sumS #-}


-- | Sequential sum the innermost dimension of an array.
sumP	:: (Shape sh, Num a, Elt a, Unbox a, Repr r a)
	=> Array r (sh :. Int) a
	-> Array U sh a
sumP = foldP (+) 0
{-# INLINE [3] sumP #-}


-- sumAll ---------------------------------------------------------------------
-- | Sequential sum of all the elements of an array.
sumAllS	:: (Shape sh, Elt a, Unbox a, Num a, Repr r a)
	=> Array r sh a
	-> a
sumAllS = foldAllS (+) 0
{-# INLINE [3] sumAllS #-}


-- | Parallel sum all the elements of an array.
sumAllP	:: (Shape sh, Elt a, Unbox a, Num a, Repr r a)
	=> Array r sh a
	-> a
sumAllP = foldAllP (+) 0
{-# INLINE [3] sumAllP #-}


-- Equality ------------------------------------------------------------------
instance (Shape sh, Repr r e, Eq e) => Eq (Array r sh e) where
 (==) arr1 arr2
        =   extent arr1 == extent arr2
        && (foldAllS (&&) True (R.zipWith (==) arr1 arr2))


-- | Check whether two arrays have the same shape and contain equal elements,
--   in parallel.
equalsP :: (Shape sh, Repr r1 e, Repr r2 e, Eq e) 
        => Array r1 sh e 
        -> Array r2 sh e
        -> Bool
equalsP arr1 arr2
        =   extent arr1 == extent arr2
        && (foldAllP (&&) True (R.zipWith (==) arr1 arr2))


-- | Check whether two arrays have the same shape and contain equal elements,
--   sequentially.
equalsS :: (Shape sh, Repr r1 e, Repr r2 e, Eq e) 
        => Array r1 sh e 
        -> Array r2 sh e
        -> Bool
equalsS arr1 arr2
        =   extent arr1 == extent arr2
        && (foldAllS (&&) True (R.zipWith (==) arr1 arr2))
