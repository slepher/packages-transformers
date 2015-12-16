{-# LANGUAGE CPP #-}
#if __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Safe #-}
#endif
#if __GLASGOW_HASKELL__ >= 710
{-# LANGUAGE AutoDeriveTypeable #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Applicative.Lift
-- Copyright   :  (c) Ross Paterson 2010
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  R.Paterson@city.ac.uk
-- Stability   :  experimental
-- Portability :  portable
--
-- Adding a new kind of pure computation to an applicative functor.
-----------------------------------------------------------------------------

module Control.Applicative.Lift (
    -- * Lifting an applicative
    Lift(..),
    unLift,
    mapLift,
    -- * Collecting errors
    Errors,
    runErrors,
    failure
  ) where

import Data.Functor.Classes

import Control.Applicative
import Data.Foldable (Foldable(foldMap))
import Data.Functor.Constant
import Data.Monoid (Monoid(..))
import Data.Traversable (Traversable(traverse))

-- | Applicative functor formed by adding pure computations to a given
-- applicative functor.
data Lift f a = Pure a | Other (f a)

instance (Eq1 f) => Eq1 (Lift f) where
    eqWith eq (Pure x1) (Pure x2) = eq x1 x2
    eqWith _ (Pure _) (Other _) = False
    eqWith _ (Other _) (Pure _) = False
    eqWith eq (Other y1) (Other y2) = eqWith eq y1 y2

instance (Ord1 f) => Ord1 (Lift f) where
    compareWith comp (Pure x1) (Pure x2) = comp x1 x2
    compareWith _ (Pure _) (Other _) = LT
    compareWith _ (Other _) (Pure _) = GT
    compareWith comp (Other y1) (Other y2) = compareWith comp y1 y2

instance (Read1 f) => Read1 (Lift f) where
    readsPrecWith rp rl = readsData $
        readsUnaryWith rp "Pure" Pure `mappend`
        readsUnaryWith (readsPrecWith rp rl) "Other" Other

instance (Show1 f) => Show1 (Lift f) where
    showsPrecWith sp _ d (Pure x) = showsUnaryWith sp "Pure" d x
    showsPrecWith sp sl d (Other y) =
        showsUnaryWith (showsPrecWith sp sl) "Other" d y

instance (Eq1 f, Eq a) => Eq (Lift f a) where (==) = eq1
instance (Ord1 f, Ord a) => Ord (Lift f a) where compare = compare1
instance (Read1 f, Read a) => Read (Lift f a) where readsPrec = readsPrec1
instance (Show1 f, Show a) => Show (Lift f a) where showsPrec = showsPrec1

instance (Functor f) => Functor (Lift f) where
    fmap f (Pure x) = Pure (f x)
    fmap f (Other y) = Other (fmap f y)

instance (Foldable f) => Foldable (Lift f) where
    foldMap f (Pure x) = f x
    foldMap f (Other y) = foldMap f y

instance (Traversable f) => Traversable (Lift f) where
    traverse f (Pure x) = Pure <$> f x
    traverse f (Other y) = Other <$> traverse f y

-- | A combination is 'Pure' only if both parts are.
instance (Applicative f) => Applicative (Lift f) where
    pure = Pure
    Pure f <*> Pure x = Pure (f x)
    Pure f <*> Other y = Other (f <$> y)
    Other f <*> Pure x = Other (($ x) <$> f)
    Other f <*> Other y = Other (f <*> y)

-- | A combination is 'Pure' only either part is.
instance (Alternative f) => Alternative (Lift f) where
    empty = Other empty
    Pure x <|> _ = Pure x
    Other _ <|> Pure y = Pure y
    Other x <|> Other y = Other (x <|> y)

-- | Projection to the other functor.
unLift :: (Applicative f) => Lift f a -> f a
unLift (Pure x) = pure x
unLift (Other e) = e

-- | Apply a transformation to the other computation.
mapLift :: (f a -> g a) -> Lift f a -> Lift g a
mapLift _ (Pure x) = Pure x
mapLift f (Other e) = Other (f e)

-- | An applicative functor that collects a monoid (e.g. lists) of errors.
-- A sequence of computations fails if any of its components do, but
-- unlike monads made with 'ExceptT' from "Control.Monad.Trans.Except",
-- these computations continue after an error, collecting all the errors.
--
-- * @'pure' f '<*>' 'pure' x = 'pure' (f x)@
--
-- * @'pure' f '<*>' 'failure' e = 'failure' e@
--
-- * @'failure' e '<*>' 'pure' x = 'failure' e@
--
-- * @'failure' e1 '<*>' 'failure' e2 = 'failure' (e1 '<>' e2)@
--
type Errors e = Lift (Constant e)

-- | Extractor for computations with accumulating errors.
--
-- * @'runErrors' ('pure' x) = 'Right' x@
--
-- * @'runErrors' ('failure' e) = 'Left' e@
--
runErrors :: Errors e a -> Either e a
runErrors (Other (Constant e)) = Left e
runErrors (Pure x) = Right x

-- | Report an error.
failure :: e -> Errors e a
failure e = Other (Constant e)
