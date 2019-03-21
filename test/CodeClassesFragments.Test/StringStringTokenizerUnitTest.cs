// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using Xunit;

namespace CodeClassesFragments.Test
{
    public class StringStringTokenizerUnitTest
    {

        [Fact]
        public void TestParsingOfString()
        {
            string [] seps = { "w", "W", "Y", "y", "m", "M", "d" };
            string teststring = "123w123W123Y123y123m123M123d000";
            var tokenizer = new StringStringTokenizer(teststring, seps,System.StringComparison.CurrentCulture);
            var en = tokenizer.GetEnumerator();
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "w"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "W"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "Y"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "y"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "m"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "M"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("123", "d"), en.Current);
            en.MoveNext();
            Assert.Equal<(string, string)>(("000", default(string)), en.Current);

        }

    }
}
