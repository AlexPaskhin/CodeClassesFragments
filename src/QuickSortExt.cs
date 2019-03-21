// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

namespace CodeClassesFragments
{
    static partial class ShellSortExt
    {
        static class QuickSortExt
        {
            public static void Quicksort(int[] elements, int left, int right)
            {
                int currLeft = left;
                int currRight = right;
                var pivot = elements[(left + right) / 2];

                while (currLeft <= currRight)
                {
                    while (elements[currLeft] > pivot)
                    {
                        currLeft++;
                    }

                    while (elements[currRight] < pivot)
                    {
                        currRight--;
                    }

                    if (currLeft <= currRight)
                    {
                        // Swap
                        var tmp = elements[currLeft];
                        elements[currLeft] = elements[currRight];
                        elements[currRight] = tmp;
                        currLeft++;
                        currRight--;
                    }
                }

                // Recursive calls
                if (left < currRight)
                {
                    Quicksort(elements, left, currRight);
                    if (currLeft < right)
                    {
                        Quicksort(elements, currLeft, right);
                    }
                }

            }
        }
    }
