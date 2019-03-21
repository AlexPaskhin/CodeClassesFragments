// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0

using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Text.RegularExpressions;

namespace CodeClassesFragments
{
    public enum ParsedType
    {
        ExpValue,
        ExpOperation,
        ExpOpenBracket,
        ExpCloseBracket,
    }

    public class ParsedElement
    {
        public string Element { get; set; }
        public ParsedType ElementType { get; set; }
    }

    public class FunctionalService 
    {

        public List<ParsedElement> ParseExpression(String expression)
        {
            List<ParsedElement> result = new List<ParsedElement>();
            Regex MyRegex = new Regex("(?<Value>\\d+\\.?\\d*)+|(?<Operation>[\\-\\+\\*\\/\\^])+|(?<OpenBracket>[\\(])+|(?<CloseBracket>[\\)])+",
               RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.IgnorePatternWhitespace | RegexOptions.Compiled);

            /// Capture all Matches in the InputText
            MatchCollection ms = MyRegex.Matches(expression);
            string wk;

            // Walk trough matches and fill parsed list 
            foreach (Match mach in ms)
            {
                wk = mach.Groups["Value"].Value;
                if (!String.IsNullOrEmpty(wk))
                {
                    result.Add(new ParsedElement() { Element = wk, ElementType = ParsedType.ExpValue });
                }

                wk = mach.Groups["Operation"].Value;
                if (!String.IsNullOrEmpty(wk))
                {
                    result.Add(new ParsedElement() { Element = wk, ElementType = ParsedType.ExpOperation });
                }

                wk = mach.Groups["OpenBracket"].Value;
                if (!String.IsNullOrEmpty(wk))
                {
                    result.Add(new ParsedElement() { Element = wk, ElementType = ParsedType.ExpOpenBracket });
                }

                wk = mach.Groups["CloseBracket"].Value;
                if (!String.IsNullOrEmpty(wk))
                {
                    result.Add(new ParsedElement() { Element = wk, ElementType = ParsedType.ExpCloseBracket });
                }
            }
            return result;
        }

        public List<ParsedElement> RPNConvertor(List<ParsedElement> parsedElements)
        {
            List<ParsedElement> result = new List<ParsedElement>();
            Stack<ParsedElement> operatorStack = new Stack<ParsedElement>();
            foreach (var item in parsedElements)
            {

                if (item.ElementType == ParsedType.ExpOpenBracket)
                {
                    operatorStack.Push(item);
                }
                else if (item.ElementType == ParsedType.ExpCloseBracket)
                {
                    while (operatorStack.Count != 0 && operatorStack.Peek().ElementType != ParsedType.ExpOpenBracket)
                    {
                        result.Add(operatorStack.Pop());
                    }

                    if (operatorStack.Count != 0 && operatorStack.Peek().ElementType == ParsedType.ExpOpenBracket)
                    {
                        operatorStack.Pop();
                    }

                }
                else if (item.ElementType == ParsedType.ExpValue)
                {
                    result.Add(item);
                }
                else if (item.ElementType == ParsedType.ExpOperation)
                {
                    while (operatorStack.Count != 0 && operatorStack.Peek().ElementType != ParsedType.ExpOpenBracket)
                    {

                        if (OperationPriority(operatorStack.Peek()) >= OperationPriority(item))
                        {

                            result.Add(operatorStack.Pop()); ;
                        }
                        else
                        {
                            break;
                        }
                    }
                    operatorStack.Push(item);
                }

            }

            while (operatorStack.Count != 0)
            {
                result.Add(operatorStack.Pop());
            }

            return result;
        }

        static string operationSignature = "=+-*/^";
        static int[] operationPriority = { 0, 1, 1, 2, 2, 3 };

        int OperationPriority(ParsedElement operation)
        {
            int result = operationSignature.IndexOf(operation.Element[0]);
            if (result > 0)
            {
                result = operationPriority[result];
            }
            return result;
        }


        public Expression CreateExpession(List<ParsedElement> parsedElements)
        {

            Expression result = Expression.Block(typeof(int));

            foreach (var item in parsedElements)
            {

                // TODO: Using System.Linq.Expressions.Expression static methods form the expression tree

            }
            return result;
        }

        public int CalculateExpression(String expression)
        {
            List<ParsedElement> parsedExp = ParseExpression(expression);
            Expression expr = CreateExpession(parsedExp);

            //TODO: execute expression
            //return result
            return 0;
        }


    }
}
