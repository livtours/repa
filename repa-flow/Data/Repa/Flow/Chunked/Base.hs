
module Data.Repa.Flow.Chunked.Base
        ( Sources, Sinks
        , Flow
        , fromList_i
        , fromLists_i
        , toList1_i
        , toLists1_i
        , head_i
        , finalize_i
        , finalize_o)
where
import qualified Data.Sequence                  as Q
import qualified Data.Foldable                  as Q
import Data.Repa.Flow.States
import Data.Repa.Array                          as A
import Data.Repa.Eval.Array                     as A
import qualified Data.Repa.Flow.Generic         as G
import Control.Monad
import Prelude                                  as P

-- | A bundle of sources, where the elements are chunked into arrays.
type Sources i m r e
        = G.Sources i m (A.Vector r e)


-- | A bundle of sinks,   where the elements are chunked into arrays.
type Sinks   i m r e
        = G.Sinks   i m (A.Vector r e)


-- | Shorthand for common type classes.
type Flow i m r a
        = (Ord i, Monad m, Bulk r DIM1 a, States i m)


-- Conversion -----------------------------------------------------------------
-- | Given an arity and a list of elements, yield sources that each produce all
--   the elements. All elements are stuffed into a single chunk, and each 
--   stream is given the same chunk.
fromList_i 
        :: (States i m, A.Target r a t)
        => i -> [a] -> m (Sources i m r a)

fromList_i n xs
 = G.fromList n [A.vfromList xs]
{-# INLINE [2] fromList_i #-}


-- | Like `fromLists_i` but take a list of lists, where each of the inner
--   lists is packed into a single chunk.
fromLists_i 
        :: (States i m, A.Target r a t)
        => i -> [[a]] -> m (Sources i m r a)

fromLists_i n xs
 = G.fromList n $ P.map A.vfromList xs
{-# INLINE [2] fromLists_i #-}


-- | Drain a single source into a list of elements.
toList1_i 
        :: (States i m, A.Bulk r DIM1 a)
        => Sources i m r a -> Ix i -> m [a]
toList1_i sources i
 = do   chunks  <- G.toList1 sources i
        return  $ P.concat $ P.map A.toList chunks
{-# INLINE [2] toList1_i #-}


-- | Drain a single source into a list of chunks.
toLists1_i
        :: (States i m, A.Bulk r DIM1 a)
        => Sources i m r a -> Ix i -> m [[a]]
toLists1_i sources i
 = do   chunks  <- G.toList1 sources i
        return  $ P.map A.toList chunks
{-# INLINE [2] toLists1_i #-}


-- | Split the given number of elements from the head of a source,
--   retrurning those elements in a list, and yielding a new source
--   for the rest.
--
--   * We pull /whole chunks/ from the source stream until we have
--     at least the desired number of elements. The leftover elements
--     in the final chunk are visible in the result `Sources`.
--
head_i  :: (States i m, A.Bulk r DIM1 a, A.Target r a t)
        => Int -> Sources i m r a -> Ix i -> m ([a], Sources i m r a)

head_i len s0 i
 = do   
        (s1, s2) <- G.connect_i s0

        let G.Sources n pull_chunk = s1

        -- Pull chunks from the source until we have enough elements to return.
        refs    <- newRefs n Q.empty
        let loop_takeList1 !has !acc
             | has >= len        = writeRefs refs i acc
             | otherwise         = pull_chunk i eat_toList eject_toList
             where eat_toList x  = loop_takeList1 
                                        (has + A.length x) 
                                        (acc Q.>< (Q.fromList $ A.toList x))
                   eject_toList  = writeRefs refs i acc
            {-# INLINE loop_takeList1 #-}

        loop_takeList1 0 Q.empty

        -- Split off the required number of elements.
        has     <- readRefs refs i
        let (here, rest) = Q.splitAt len has

        -- As we've pulled whole chunks from the input stream,
        -- we now prepend the remaining ones back on.
        s2'     <- G.prependOn_i (\i' -> i' == i) 
                        [A.vfromList $ Q.toList rest] 
                        s2

        return  (Q.toList here, s2')
{-# INLINE [2] head_i #-}


-- Finalizers -----------------------------------------------------------------
-- | Attach a finalizer to a bundle of sources.
--
--   For each stream in the bundle, the finalizer will be called the first
--   time a consumer of that stream tries to pull an element when no more
--   are available.
--
--   The provided finalizer will be run after any finalizers already
--   attached to the source.
--
finalize_i
        :: States i m
        => (Ix i -> m ())
        -> Sources i m r a -> m (Sources i m r a)
finalize_i = G.finalize_i
{-# INLINE [2] finalize_i #-}


-- | Attach a finalizer to a bundle of sinks.
--
--   The finalizer will be called the first time the stream is ejected.
--
--   The provided finalizer will be run after any finalizers already
--   attached to the sink.
--
finalize_o
        :: States i m
        => (Ix i -> m ())
        -> Sinks i m r a -> m (Sinks i m r a)
finalize_o = G.finalize_o
{-# INLINE [2] finalize_o #-}