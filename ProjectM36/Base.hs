{-# LANGUAGE GADTs,DeriveGeneric #-}
module ProjectM36.Base where
import qualified Data.Map as M
import qualified Data.HashSet as HS
import qualified Data.Hashable as Hash
import qualified Data.Set as S
import Control.Monad.State hiding (join)
import Data.UUID (UUID)
import Control.DeepSeq (NFData, rnf)
import Control.DeepSeq.Generics (genericRnf)
import GHC.Generics (Generic)

data Atom = StringAtom String |
            IntAtom Int |
            RelationAtom Relation deriving (Show, Eq, Generic)
                                           
instance NFData Atom where rnf = genericRnf                  

data AtomType = StringAtomType |
                IntAtomType |
                RelationAtomType Attributes deriving (Eq, Show, Generic)
                                                     
instance NFData AtomType where rnf = genericRnf
                                                     
atomTypeForAtom :: Atom -> AtomType
atomTypeForAtom (StringAtom _) = StringAtomType
atomTypeForAtom (IntAtom _) = IntAtomType
atomTypeForAtom (RelationAtom (Relation attributes _)) = RelationAtomType attributes

type AttributeName = String
type AtomName = String

data Attribute = Attribute AttributeName AtomType deriving (Eq, Show, Generic)

instance NFData Attribute where rnf = genericRnf

type Attributes = M.Map AttributeName Attribute --attributes keys by attribute name for ease of access

type RelationTupleSet = HS.HashSet RelationTuple 

instance Hash.Hashable RelationTuple where
  hashWithSalt salt tup = Hash.hashWithSalt salt (show tup)
  
data RelationTuple = RelationTuple (M.Map AttributeName Atom) deriving (Eq, Show, Generic)

instance NFData RelationTuple where rnf = genericRnf

data Relation = Relation Attributes RelationTupleSet deriving (Show, Eq, Generic)

instance NFData Relation where rnf = genericRnf
  
data RelationCardinality = Uncountable | Countable Int deriving (Eq, Show, Generic)
data RelationSizeInfinite = RelationSizeInfinite

data RelationalExpr where
  MakeStaticRelation :: Attributes -> RelationTupleSet -> RelationalExpr
  --MakeFunctionalRelation (creates a relation from a tuple-generating function, potentially infinite)
  --in Tutorial D, relational variables pick up the type of the first relation assigned to them
  --relational variables should also be able to be explicitly-typed like in Haskell
  RelationVariable :: String -> RelationalExpr
  Project :: S.Set AttributeName -> RelationalExpr -> RelationalExpr
  Union :: RelationalExpr -> RelationalExpr -> RelationalExpr
  Join :: RelationalExpr -> RelationalExpr -> RelationalExpr
  Rename :: AttributeName -> AttributeName -> RelationalExpr -> RelationalExpr
  Group :: S.Set AttributeName -> AttributeName -> RelationalExpr -> RelationalExpr
  Ungroup :: AttributeName -> RelationalExpr -> RelationalExpr
  Restrict :: RestrictionPredicateExpr -> RelationalExpr -> RelationalExpr  
  Equals :: RelationalExpr -> RelationalExpr -> RelationalExpr
{- maybe break this into multiple steps:
1. check relational types for match (attribute counts) (typechecking step
2. create an execution plan (another system of nodes, another GADT)
3. execute the plan
-}
  deriving (Show,Eq)

data DatabaseContext = DatabaseContext { 
  inclusionDependencies :: HS.HashSet InclusionDependency,
  relationVariables :: M.Map String Relation
  } deriving (Show)
             
data InclusionDependency = InclusionDependency String RelationalExpr RelationalExpr deriving (Show)

instance Hash.Hashable InclusionDependency where
  hashWithSalt salt dep = Hash.hashWithSalt salt (show dep)
  
instance Eq InclusionDependency where
  (==) (InclusionDependency nameA _ _) (InclusionDependency nameB _ _) = nameA == nameB

--Database context expressions modify the database context while relational expressions do not
data DatabaseExpr where
  Define :: String -> Attributes -> DatabaseExpr
  Undefine :: String -> DatabaseExpr --forget existence of relvar X
  Assign :: String -> RelationalExpr -> DatabaseExpr
  Insert :: String -> RelationalExpr -> DatabaseExpr
  Delete :: String -> RestrictionPredicateExpr -> DatabaseExpr 
  Update :: String -> M.Map String Atom -> RestrictionPredicateExpr -> DatabaseExpr -- needs restriction support
  AddInclusionDependency :: InclusionDependency -> DatabaseExpr
  MultipleExpr :: [DatabaseExpr] -> DatabaseExpr
  deriving (Show,Eq)

type DatabaseState a = State DatabaseContext a

data RestrictionPredicateExpr where
  TruePredicate :: RestrictionPredicateExpr
  AndPredicate :: RestrictionPredicateExpr -> RestrictionPredicateExpr -> RestrictionPredicateExpr
  OrPredicate :: RestrictionPredicateExpr -> RestrictionPredicateExpr -> RestrictionPredicateExpr
  NotPredicate :: RestrictionPredicateExpr -> RestrictionPredicateExpr
  RelationalExprPredicate :: RelationalExpr -> RestrictionPredicateExpr --type must be same as true and false relations (no attributes)
  AttributeEqualityPredicate :: AttributeName -> Atom -> RestrictionPredicateExpr -- relationalexpr must result in relation with single tuple
  deriving (Show, Eq)

-- child + parent links
-- the string represents the branch name and can be used to find the named HEADs
type HeadName = String

type TransactionHeads = M.Map HeadName Transaction

data TransactionGraph = TransactionGraph TransactionHeads (S.Set Transaction)
                        deriving (Show, Eq)

transactionsForGraph :: TransactionGraph -> S.Set Transaction
transactionsForGraph (TransactionGraph _ t) = t

transactionHeadsForGraph :: TransactionGraph -> TransactionHeads
transactionHeadsForGraph (TransactionGraph heads _) = heads

data TransactionInfo = TransactionInfo UUID (S.Set UUID) | -- 1 parent + n children
                       MergeTransactionInfo UUID UUID (S.Set UUID) -- 2 parents, n children
                     deriving(Show)
                             
data Transaction = Transaction UUID TransactionInfo DatabaseContext -- self uuid
                   deriving (Show)
                            
--represents an "in-progress" transaction which has not yet been added to the transaction graph
--one the transaction is "complete", it is committed and no longer can be changed
-- this is similar to the index in git
data DisconnectedTransaction = DisconnectedTransaction UUID DatabaseContext --parentUUID, context
                            
transactionUUID :: Transaction -> UUID
transactionUUID (Transaction uuid _ _) = uuid

transactionContext :: Transaction -> DatabaseContext
transactionContext (Transaction _ _ context) = context
                            
instance Eq Transaction where                            
  (Transaction uuidA _ _) == (Transaction uuidB _ _) = uuidA == uuidB
                   
instance Ord Transaction where                            
  compare (Transaction uuidA _ _) (Transaction uuidB _ _) = compare uuidA uuidB
