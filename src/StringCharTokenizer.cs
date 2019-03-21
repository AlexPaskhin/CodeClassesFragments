// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using System.Collections;
using System.Collections.Generic;
using System.Text;

namespace CodeClassesFragments
{
    public class StringCharTokenizer : IEnumerable<(string, char)>
    {
        private string _input;
        private char[] _separators;
        public StringCharTokenizer(string inputString, char[] separators)
        {
            _input = inputString;
            _separators = separators;
        }

        public IEnumerator<(string, char)> GetEnumerator()
        {
            return new _StringCharTokenizer(_input, _separators);
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return new _StringCharTokenizer(_input, _separators);
        }

        class _StringCharTokenizer : IEnumerator<(string, char)>
        {
            private string _input;
            private char[] _separators;
            private (string, char) _current;

            public _StringCharTokenizer(string inputString, char[] separators)
            {
                _input = inputString;
                _separators = separators;
                _current = default((string, char));
            }

            public (string, char) Current
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

                char sep = default(char);
                int next = _input.IndexOfAny(_separators,_index);
                if (next == -1)
                {
                    next = _input.Length;
                }
                else
                {
                    sep = _input[next];
                }
                Current = (_input.Substring(_index, next - _index), sep);
                _index = next + 1;
                return true;
            }

            public void Reset()
            {
                _current = default((string, char));
                _index = 0;
            }
        }
    }
}
