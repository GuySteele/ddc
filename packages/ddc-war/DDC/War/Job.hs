{-# LANGUAGE ExistentialQuantification #-}
module DDC.War.Job where
import DDC.War.Driver.Base
import qualified DDC.War.Job.CompileDCE as CompileDCE
import qualified DDC.War.Job.CompileDS  as CompileDS
import qualified DDC.War.Job.CompileHS  as CompileHS
import qualified DDC.War.Job.Diff       as Diff
import qualified DDC.War.Job.RunDCX     as RunDCX
import qualified DDC.War.Job.RunExe     as RunExe
import qualified DDC.War.Job.Shell      as Shell
import BuildBox.Pretty


instance Spec CompileDCE.Spec CompileDCE.Result where
 buildFromSpec                  
  = CompileDCE.build
 productOfResult spec result    
  = ProductStatus "compile" 
        (CompileDCE.specWayName  spec) 
        (CompileDCE.specTestName spec) (ppr result)


instance Spec CompileDS.Spec  CompileDS.Result where
 buildFromSpec  = CompileDS.build
 productOfResult spec result    
  = ProductStatus "compile" 
        (CompileDS.specWayName  spec)
        (CompileDS.specTestName spec) (ppr result)


instance Spec CompileHS.Spec  CompileHS.Result where
 buildFromSpec  = CompileHS.build
 productOfResult spec result    
  = ProductStatus "compile" 
        (CompileHS.specWayName  spec)
        (CompileHS.specTestName spec) (ppr result)


instance Spec Diff.Spec       Diff.Result where
 buildFromSpec  = Diff.build
 productOfResult spec r
  = case r of
        Diff.ResultSame                 
         -> ProductStatus "diff" 
                (Diff.specWayName  spec)
                (Diff.specTestName spec) (ppr r)

        Diff.ResultDiff ref out diff    
         -> ProductDiff "diff"   
                (Diff.specWayName  spec)
                (Diff.specTestName spec) ref out diff


instance Spec RunDCX.Spec     RunDCX.Result where
 buildFromSpec  = RunDCX.build
 productOfResult spec result    
  = ProductStatus "run" 
        (RunDCX.specWayName  spec)
        (RunDCX.specTestName spec) (ppr result)


instance Spec RunExe.Spec     RunExe.Result where
 buildFromSpec  = RunExe.build
 productOfResult spec result    
  = ProductStatus "run" 
        (RunExe.specWayName  spec)
        (RunExe.specTestName spec) (ppr result)


instance Spec Shell.Spec      Shell.Result where
 buildFromSpec  = Shell.build
 productOfResult spec result    
  = ProductStatus "shell" 
        (Shell.specWayName  spec)
        (Shell.specTestName spec) (ppr result)




