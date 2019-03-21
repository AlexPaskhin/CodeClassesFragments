// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using System;

namespace CodeClassesFragments
{
    static partial class ShellSortExt
    {
        public static void ShellSort(ref int[] iray)
        {
            int j;
            int increment = iray.Length / 2;
            while (increment > 0)
            {
                Console.WriteLine("increment = " + increment);
                for (int i = 1 + increment; i < iray.Length; i++)
                {
                    int tmp = iray[i];
                    j = i;

                    while (j - increment >= 0)
                    {

                        // printArray(iray);
                        if (iray[j - increment] > tmp)
                        {
                            Console.WriteLine(" copying " + iray[j] + " to " + iray[j - increment]);
                            Console.WriteLine("index copying " + j + " to " + (j - increment));
                            iray[j] = iray[j - increment];
                            //tmp = iray[j - increment];

                        }
                        else
                        {
                            break;
                        }
                        j = j - increment;
                    }
                    iray[j] = tmp;

                }

                increment = increment / 2;
            }
        }
    }
}
