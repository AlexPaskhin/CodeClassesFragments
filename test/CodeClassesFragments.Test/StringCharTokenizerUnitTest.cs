// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using System;
using Xunit;

namespace CodeClassesFragments.Test
{
    public class StringCharTokenizerUnitTest
    {

        [Fact]
        public void TestParsingOfString()
        {
            char[] seps = { 'w', 'W', 'Y', 'y', 'm', 'M', 'd' };
            string teststring = "123w123W123Y123y123m123M123d000";
            var tokenizer = new StringCharTokenizer(teststring, seps);
            var en = tokenizer.GetEnumerator();
            en.MoveNext();
            Assert.Equal<(string,char)>(("123", 'w'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("123", 'W'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("123", 'Y'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("123", 'y'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("123", 'm'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("123", 'M'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("123", 'd'), en.Current);
            en.MoveNext();
            Assert.Equal<(string, char)>(("000", default(char)), en.Current);

        }

    }
}
