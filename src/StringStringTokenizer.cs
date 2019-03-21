// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using System;
using System.Collections;
using System.Collections.Generic;

namespace CodeClassesFragments
{
    public class StringStringTokenizer : IEnumerable<(string, string)>
    {
        private string _input;
        private string[] _separators;
        private StringComparison _stringComparison;

        public StringStringTokenizer(string inputString, string[] separators, StringComparison stringComparison)
        {
            _input = inputString;
            _separators = separators;
            _stringComparison = stringComparison;
        }

        public IEnumerator<(string, string)> GetEnumerator()
        {
            return new _StringCharTokenizer(_input, _separators, _stringComparison);
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return new _StringCharTokenizer(_input, _separators, _stringComparison);
        }

        class _StringCharTokenizer : IEnumerator<(string, string)>
        {
            private string _input;
            private string[] _separators;
            private StringComparison _stringComparison;
            private (string, string) _current;

            public _StringCharTokenizer(string inputString, string[] separators, StringComparison stringComparison)
            {
                _input = inputString;
                _separators = separators;
                _stringComparison = stringComparison;
                _current = default((string, string));
            }

            public (string, string) Current
            {
                get => _current;
                set => _current = value;
            }

            object IEnumerator.Current => _current;

            public void Dispose()
            {
            }

            int _index = 0;
            public bool MoveNext()
            {
                if (string.IsNullOrEmpty(_input) || _index >= _input.Length)
                {
                    return false;
                }

                string sep = default(string);
                int next = -1;
                foreach (var s in _separators)
                {
                    next = _input.IndexOf(s, _index, _stringComparison);
                    if (next != -1)
                    {
                        sep = s;
                        break;
                    }
                }
                if (next == -1)
                {
                    next = _input.Length;
                }

                Current = (_input.Substring(_index, next - _index), sep);
                _index = next + 1;
                return true;
            }

            public void Reset()
            {
                _current = default((string, string));
                _index = 0;
            }
        }
    }
}
