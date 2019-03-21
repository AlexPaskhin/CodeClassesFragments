// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using System.Collections.Generic;
using System.Linq;

namespace CodeClassesFragments
{


    class Fibonacci
    {

        public int FibonacciNumber(int index)
        {
            int res = 0;
            if (index > 0)
            {
                res = FibonacciNumbers().Skip(index).First();
            }
            return res;
        }

        static public IEnumerable<int> FibonacciNumbers()
        {
            int f0 = 0;
            int f1 = 1;
            yield return f0;
            yield return f1;
            while (true)
            {
                int result = f0 + f1;
                f0 = f1;
                f1 = result;
                yield return result;
            }
        }

    }
}
