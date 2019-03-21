// Copyright © Alexander Paskhin 2018. All rights reserved.
//  Licensed under GNU General Public License v3.0


using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Threading.Tasks.Dataflow;

namespace CodeClassesFragments
{
    /// <summary>
    /// The base class to provide enrichment functions. It provide the support of TPL dataflow patterns.
    /// </summary>
    public class BaseProcessorActionBlock<T> : IDisposable
    {
        public ActionBlock<T> ProxyActionBlock { get; set; }

        /// <summary>
        /// Used to synchronize action block cancellation to other external process.
        /// </summary>
        public CancellationTokenSource CancellationTokenSourceActionBlock { get; } = new CancellationTokenSource();

        CancellationTokenRegistration _cancellationTokenRegistrationLocal;
        CancellationToken _cancellationToken;

        public void Cancel()
        {
            CancellationTokenSourceActionBlock.Cancel();
            Task.Yield();
        }

        /// <summary>
        /// The cancellation token source that used to cancel all operations. The processor 
        /// become unusable after it was triggering it.
        /// </summary>
        public CancellationToken CancellationToken
        {
            get { return _cancellationToken; }
            set
            {
                _cancellationToken = value;
                _cancellationTokenRegistrationLocal.Dispose();
                if (_cancellationToken.IsCancellationRequested)
                {
                    CancellationTokenSourceActionBlock.Cancel();
                    Task.Yield();
                }
                else
                {
                    _cancellationTokenRegistrationLocal = _cancellationToken.Register(CancellationRequested);
                }
            }
        }

        /// <summary>
        /// The optional values that should send for a processor action.
        /// </summary>
        public Dictionary<string, object> Properties { get; } = new Dictionary<string, object>();

        /// <summary>
        /// Constructs the class of the simple processing logics.
        /// </summary>
        /// <param name="performedAction">The action that has been performed.</param>
        /// <param name="maxDegreeofParallelism">The maximum degree of parallelism for performed actions.</param>
        public BaseProcessorActionBlock(Action<T, Dictionary<string, object>> performedAction, int maxDegreeofParallelism = 1)
        {
            PerformedAction = performedAction;
            _cancellationToken = CancellationTokenSourceActionBlock.Token;
            ExecutionDataflowBlockOptions dataflowBlockOptions = new ExecutionDataflowBlockOptions()
            {
                MaxDegreeOfParallelism = maxDegreeofParallelism,
                CancellationToken = _cancellationToken
            };
            ProxyActionBlock = new ActionBlock<T>((Action<T>)ProxyProcessorAction, dataflowBlockOptions);
        }

        /// <summary>
        /// The actual delegate that performs an action.
        /// </summary>
        public Action<T, Dictionary<string, object>> PerformedAction { get; protected set; }

        protected void CancellationRequested()
        {
            CancellationTokenSourceActionBlock.Cancel();
            Task.Yield();
        }

        void ProxyProcessorAction(T request)
        {
            try
            {
                if (!_cancellationToken.IsCancellationRequested && !_disposedValue)
                {
                    PerformedAction(request, Properties);
                }
            }
            catch { }
        }

        #region IDisposable Support
        private bool _disposedValue; // To detect redundant calls

        protected virtual void Dispose(bool disposing)
        {
            if (!_disposedValue)
            {
                if (disposing)
                {
                    if (ProxyActionBlock.Completion.Status == TaskStatus.Running)
                    {
                        CancellationTokenSourceActionBlock.Cancel();
                        Task.Yield();
                    }
                }
                _disposedValue = true;
            }
        }

        // This code added to correctly implement the disposable pattern.
        public void Dispose()
        {
            Dispose(true);
        }
        #endregion
    }
}