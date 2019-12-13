namespace VRTK.Examples.Tests
{
    using UnityEngine;
    using System.Collections;

    public abstract class VRTK_BaseTest : MonoBehaviour
    {
        protected string currentTest;
        protected string currentSetup;

        protected abstract void Test();

        protected virtual void OnEnable()
        {
            StartCoroutine(RunTests());
        }

        protected virtual void BeginTest(string name, int level = 1)
        {
            currentTest = name;
            VRTK_Logger.Info("<color=darkblue><b>" + "".PadLeft(level, '#') + " Starting Tests for " + name + "</b></color>");
        }

        protected virtual void SetUp(string message)
        {
            currentSetup = message;
            VRTK_Logger.Info("<color=blue><b>#### Preparing test for " + message + "</b></color>");
        }

        protected virtual void TearDown()
        {
            VRTK_Logger.Info("==============================================================================");
        }

        protected virtual void Assert(string description, bool assertion, string failure, string success = "")
        {
            if (assertion)
            {
                VRTK_Logger.Info("<color=teal><b>## [" + description + "] PASSED ##</b></color>");
            }
            else
            {
                VRTK_Logger.Info("<color=maroon><b>## [" + description + "] FAILED INSIDE [" + currentTest + "." + currentSetup + "]##</b></color>");
            }

            if (!assertion)
            {
                VRTK_Logger.Error(new System.Exception(failure));
            }
            else if (success != "")
            {
                VRTK_Logger.Info("<color=purple><i> ~~~~~> " + success + "</i></color>");
            }
        }

        protected virtual IEnumerator RunTests()
        {
            yield return new WaitForEndOfFrame();
            Test();
        }
    }
}
